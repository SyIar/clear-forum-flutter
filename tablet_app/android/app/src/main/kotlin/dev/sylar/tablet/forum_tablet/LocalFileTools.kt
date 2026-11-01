package dev.sylar.tablet.forum_tablet

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.util.AtomicFile
import net.lingala.zip4j.ZipFile
import net.lingala.zip4j.exception.ZipException
import org.json.JSONObject
import java.io.DataInputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import java.util.zip.CRC32

class FileToolFailure(val code: String) : Exception(code)

/** File jobs survive route changes. Passwords never enter preferences or logs. */
object LocalFileTools {
    private val executor = Executors.newSingleThreadExecutor()
    private val stateLock = Any()
    private var state: Map<String, Any> = mapOf("state" to "idle")
    private val sourceLocks = mutableSetOf<String>()
    fun status(): Map<String, Any> = synchronized(stateLock) { state.toMap() }
    fun busy(path: String): Boolean = synchronized(stateLock) {
        sourceLocks.any { it == path || it.startsWith(path + File.separator) || path.startsWith(it + File.separator) }
    }

    fun start(context: Context, operation: String, path: String, password: String?): Map<String, Any> {
        if (operation !in setOf("extract", "convert")) throw FileToolFailure("Unsupported operation")
        val app = context.applicationContext
        val source = checked(DownloadService.directory(app), File(path))
        if (DownloadService.busyPath(app, source.path)) throw FileToolFailure("File is downloading")
        val secret = password?.toCharArray()
        synchronized(stateLock) {
            if (state["state"] == "running") {
                secret?.fill(0.toChar())
                throw FileToolFailure("File job already running")
            }
            state = mapOf("id" to UUID.randomUUID().toString(), "state" to "running", "operation" to operation, "name" to source.name,
                "source" to source.path,
                "completed" to 0, "total" to 0, "saved" to 0L)
            sourceLocks.add(source.path)
        }
        executor.execute {
            try {
                val root = DownloadService.directory(app)
                if (operation == "extract") {
                    val result = extract(root, source, secret) { count, total -> progress(count, total) }
                    finish(mapOf("path" to result.path))
                } else {
                    val sources = if (source.isDirectory) {
                        source.walkTopDown().onEnter { !Files.isSymbolicLink(it.toPath()) && !it.name.startsWith(".") }
                            .filter { it.isFile && it.extension.equals("png", true) && !Files.isSymbolicLink(it.toPath()) }
                            .take(50001).toList()
                    } else listOf(source)
                    if (sources.size > 50000) throw FileToolFailure("Too many files")
                    var converted = 0
                    var saved = 0L
                    var failed = 0
                    for ((index, file) in sources.withIndex()) {
                        val result = try {
                            if (DownloadService.busyPath(app, file.canonicalPath)) null else convert(app, root, file)
                        } catch (_: Exception) { failed++; null }
                          catch (_: OutOfMemoryError) { failed++; null }
                        if (result != null) { converted++; saved += result.second }
                        progress(index + 1, sources.size, saved, converted)
                    }
                    finish(mapOf("converted" to converted, "saved" to saved, "failed" to failed,
                        "skipped" to sources.size - converted - failed))
                }
            } catch (error: Exception) {
                synchronized(stateLock) {
                    state = state + mapOf("state" to "failed", "error" to errorCode(error))
                }
            } catch (_: OutOfMemoryError) {
                synchronized(stateLock) { state = state + mapOf("state" to "failed", "error" to "File operation failed") }
            } finally {
                secret?.fill(0.toChar())
                synchronized(stateLock) { sourceLocks.remove(source.path) }
            }
        }
        return status()
    }

    fun automaticallyConvert(context: Context, file: File) {
        if (!file.extension.equals("png", true)) return
        val app = context.applicationContext
        executor.execute {
            synchronized(stateLock) { sourceLocks.add(file.path) }
            try { convert(app, DownloadService.directory(app), file) }
            catch (_: Exception) { /* A failed optimization always retains the original. */ }
            catch (_: OutOfMemoryError) { /* Keep large images intact under memory pressure. */ }
            finally { synchronized(stateLock) { sourceLocks.remove(file.path) } }
        }
    }

    private fun progress(completed: Int, total: Int, saved: Long = 0, converted: Int = 0) = synchronized(stateLock) {
        state = state + mapOf("completed" to completed, "total" to total, "saved" to saved, "converted" to converted)
    }
    private fun finish(values: Map<String, Any>) = synchronized(stateLock) { state = state + values + ("state" to "complete") }
    private fun errorCode(error: Exception): String = when {
        error is FileToolFailure -> error.code
        error is ZipException && error.type == ZipException.Type.WRONG_PASSWORD -> "Incorrect password"
        error is ZipException && error.type == ZipException.Type.UNSUPPORTED_ENCRYPTION -> "Unsupported encryption"
        error is ZipException -> "Invalid ZIP archive"
        else -> "File operation failed"
    }

    fun checked(root: File, input: File): File {
        val base = root.canonicalFile
        val file = input.canonicalFile
        if (file != base && !file.path.startsWith(base.path + File.separator)) throw FileToolFailure("Unsafe file path")
        var part: File? = input.absoluteFile
        while (part != null && part.path != root.absolutePath) {
            if (Files.isSymbolicLink(part.toPath())) throw FileToolFailure("Unsafe file path")
            part = part.parentFile
        }
        if (!file.exists()) throw FileToolFailure("File not found")
        return file
    }

    /** Stream each entry into a private staging directory; publish only on success. */
    fun extract(root: File, input: File, password: CharArray?, onProgress: (Int, Int) -> Unit = { _, _ -> }): File {
        val source = checked(root, input)
        if (!source.isFile || !source.extension.equals("zip", true)) throw FileToolFailure("Invalid ZIP archive")
        val parent = source.parentFile!!
        val staging = Files.createTempDirectory(parent.toPath(), ".forum-extract-").toFile()
        try {
            ZipFile(source, password).use { zip ->
                if (zip.isEncrypted && (password == null || password.isEmpty())) throw FileToolFailure("Password required")
                val headers = zip.fileHeaders
                if (headers.isEmpty() || headers.size > 50000) throw FileToolFailure("Too many files")
                val paths = HashSet<String>()
                var declared = 0L
                val limit = 128L * 1024 * 1024 * 1024
                for (header in headers) {
                    val name = header.fileName.replace('\\', '/').trimEnd('/')
                    val segments = name.split('/')
                    if (name.isEmpty() || name.startsWith('/') || name.contains(':') || name.any { it.code < 32 } ||
                        segments.any { it.isEmpty() || it == "." || it == ".." } ||
                        !paths.add(name.lowercase(Locale.ROOT))) throw FileToolFailure("Unsafe archive path")
                    val attributes = header.externalFileAttributes
                    val mode = if (attributes != null && attributes.size >= 4)
                        ((attributes[3].toInt() and 255) shl 8) or (attributes[2].toInt() and 255) else 0
                    if ((mode and 0xf000) !in setOf(0, 0x4000, 0x8000)) throw FileToolFailure("Unsafe archive path")
                    if (header.uncompressedSize < 0 || header.uncompressedSize > limit - declared) throw FileToolFailure("Archive too large")
                    declared += header.uncompressedSize
                }
                if (parent.usableSpace < declared + 16 * 1024 * 1024) throw FileToolFailure("Insufficient free space")
                var written = 0L
                for ((index, header) in headers.withIndex()) {
                    val target = File(staging, header.fileName.replace('\\', '/')).canonicalFile
                    if (!target.path.startsWith(staging.canonicalPath + File.separator)) throw FileToolFailure("Unsafe archive path")
                    if (header.isDirectory) {
                        if (!target.mkdirs() && !target.isDirectory) throw FileToolFailure("Unsafe archive path")
                    } else {
                        target.parentFile!!.mkdirs()
                        if (!target.createNewFile()) throw FileToolFailure("Duplicate archive entry")
                        var entryBytes = 0L
                        zip.getInputStream(header).use { stream ->
                            FileOutputStream(target).use { output ->
                                val buffer = ByteArray(128 * 1024)
                                while (true) {
                                    val size = stream.read(buffer)
                                    if (size < 0) break
                                    entryBytes += size; written += size
                                    if (entryBytes > header.uncompressedSize || written > limit) throw FileToolFailure("Archive too large")
                                    output.write(buffer, 0, size)
                                }
                                output.fd.sync()
                            }
                        }
                        if (entryBytes != header.uncompressedSize) throw FileToolFailure("Invalid ZIP archive")
                        target.setLastModified(System.currentTimeMillis())
                    }
                    onProgress(index + 1, headers.size)
                }
            }
            val stem = source.nameWithoutExtension.ifBlank { "archive" }
            var target = File(parent, stem)
            var suffix = 1
            while (target.exists()) target = File(parent, "$stem (${suffix++})")
            Files.move(staging.toPath(), target.toPath())
            target.setLastModified(System.currentTimeMillis())
            return target
        } finally {
            if (staging.exists() && staging.canonicalPath.startsWith(parent.canonicalPath + File.separator)) staging.deleteRecursively()
        }
    }

    private val journalLock = Any()
    private fun journal(context: Context) = AtomicFile(File(context.filesDir, "image-conversions.json"))
    private fun readJournal(context: Context): JSONObject = try {
        journal(context).openRead().use { JSONObject(it.bufferedReader().readText()) }
    } catch (error: java.io.FileNotFoundException) { JSONObject() }
    private fun hash(file: File): String {
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(128 * 1024)
            while (true) { val count = input.read(buffer); if (count < 0) break; hash.update(buffer, 0, count) }
        }
        return hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    /** Conservative PNG policy: unknown metadata, animation and wide-color files stay intact. */
    private fun supportedPng(file: File): Boolean {
        if (file.length() !in 1..(80L * 1024 * 1024)) return false
        DataInputStream(file.inputStream().buffered()).use { input ->
            if (input.readLong() != -8552249625308161526L) return false
            var ended = false
            var seenHeader = false
            var seenData = false
            var width = 0L; var height = 0L
            while (!ended) {
                val length = input.readInt()
                if (length < 0 || length > file.length() - 12) return false
                val typeBytes = ByteArray(4); input.readFully(typeBytes)
                val type = String(typeBytes, Charsets.US_ASCII)
                if (type !in setOf("IHDR", "PLTE", "tRNS", "IDAT", "IEND", "sRGB")) return false
                if (!seenHeader && type != "IHDR") return false
                val crc = CRC32(); crc.update(typeBytes)
                var left = length
                val buffer = ByteArray(minOf(65536, maxOf(length, 1)))
                while (left > 0) {
                    val count = minOf(left, buffer.size)
                    input.readFully(buffer, 0, count); crc.update(buffer, 0, count)
                    if (type == "IHDR") {
                        if (seenHeader || length != 13) return false
                        val header = java.nio.ByteBuffer.wrap(buffer)
                        width = header.int.toLong(); height = header.int.toLong()
                        if (width !in 1L..16383L || height !in 1L..16383L || width * height > 12000000 ||
                            buffer[8].toInt() != 8 || buffer[12].toInt() != 0) return false
                        seenHeader = true
                    }
                    left -= count
                }
                if ((input.readInt().toLong() and 0xffffffffL) != crc.value) return false
                if (type == "IDAT") seenData = true
                if (type == "IEND") { if (length != 0 || !seenData) return false; ended = true }
            }
            if (input.read() != -1 || width * height * 12 > Runtime.getRuntime().maxMemory() / 2) return false
        }
        return true
    }

    fun convert(context: Context, root: File, input: File): Pair<File, Long>? {
        if (Build.VERSION.SDK_INT < 30) return null
        val source = checked(root, input)
        if (!source.isFile || !source.extension.equals("png", true) || !supportedPng(source)) return null
        val before = hash(source)
        val size = source.length()
        val arrival = source.lastModified()
        val destination = File(source.parentFile, source.nameWithoutExtension + ".webp")
        if (destination.exists()) {
            checked(root, destination)
            val entry = synchronized(journalLock) { readJournal(context).optJSONObject(source.path) }
            if (entry == null || entry.optString("original") != before || entry.optString("output") != hash(destination) ||
                entry.optString("path") != destination.path || destination.length() >= size) return null
            if (hash(source) != before || !source.delete()) return null
            DownloadService.relocate(context, source.path, destination)
            return destination to (size - destination.length())
        }
        val stage = File(source.parentFile, ".forum-image-${UUID.randomUUID()}.part")
        val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888; inPremultiplied = false }
        val original = BitmapFactory.decodeFile(source.path, options) ?: return null
        try {
            if (original.colorSpace?.isSrgb != true) return null
            // Transparent hidden RGB can be discarded by platform decoders. Do not claim exact preservation for it.
            val pixels = IntArray(original.width)
            for (row in 0 until original.height) {
                original.getPixels(pixels, 0, original.width, 0, row, original.width, 1)
                if (pixels.any { (it ushr 24) != 255 }) return null
            }
            FileOutputStream(stage).use { output ->
                if (!original.compress(Bitmap.CompressFormat.WEBP_LOSSLESS, 100, output)) return null
                output.fd.sync()
            }
            if (stage.length() >= size) return null
            val restored = BitmapFactory.decodeFile(stage.path, options) ?: return null
            try {
                if (restored.width != original.width || restored.height != original.height || restored.colorSpace != original.colorSpace) return null
                val check = IntArray(original.width)
                for (row in 0 until original.height) {
                    restored.getPixels(check, 0, original.width, 0, row, original.width, 1)
                    original.getPixels(pixels, 0, original.width, 0, row, original.width, 1)
                    if (!pixels.contentEquals(check)) return null
                }
            } finally { restored.recycle() }
            if (hash(source) != before) throw FileToolFailure("File changed during conversion")
            stage.setLastModified(arrival)
            Files.move(stage.toPath(), destination.toPath())
            synchronized(journalLock) {
                val values = readJournal(context)
                values.put(source.path, JSONObject().put("path", destination.path).put("original", before).put("output", hash(destination)))
                val file = journal(context)
                val stream = file.startWrite()
                try { stream.write(values.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(stream) }
                catch (error: Exception) { file.failWrite(stream); throw error }
            }
            if (hash(source) != before || !source.delete()) throw FileToolFailure("File changed during conversion")
            DownloadService.relocate(context, source.path, destination)
            return destination to (size - destination.length())
        } finally { original.recycle(); stage.delete() }
    }

    fun resolved(context: Context, path: String): String {
        val source = File(path)
        if (source.exists() || !source.extension.equals("png", true)) return path
        return try {
            val entry = synchronized(journalLock) { readJournal(context).optJSONObject(source.canonicalPath) } ?: return path
            val output = checked(DownloadService.directory(context), File(entry.getString("path")))
            if (output.isFile && hash(output) == entry.getString("output")) output.path else path
        } catch (_: Exception) { path }
    }
}
