package dev.sylar.tablet.forum_tablet

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** The Android service owns transfers; Flutter routes never own their lifetime. */
class DownloadService : Service() {
    private val running = AtomicBoolean(false)
    @Volatile private var stopping = false
    @Volatile private var activeConnection: HttpURLConnection? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        recover(this)
        serviceAlive = true
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, getString(R.string.download_channel), NotificationManager.IMPORTANCE_LOW)
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val note = notification(getString(R.string.download_queued), -1, 0)
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(NOTIFICATION, note)
        if (running.compareAndSet(false, true)) {
            stopping = false
            Thread({
                try {
                    while (!stopping) {
                        val item = synchronized(LOCK) {
                            read(this).firstOrNull { it.optString("state") == "queued" }
                        } ?: break
                        transfer(item)
                    }
                } finally {
                    android.os.Handler(mainLooper).post {
                        running.set(false)
                        val pending = synchronized(LOCK) { read(this).any { it.optString("state") == "queued" } }
                        if (pending && !stopping) onStartCommand(null, 0, startId)
                        else { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
                    }
                }
            }, "forum-download-worker").start()
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopping = true
        synchronized(LOCK) {
            val items = read(this)
            items.filter { it.optString("state") in setOf("queued", "downloading") }.forEach { it.put("state", "paused") }
            write(this, items)
        }
        activeConnection?.disconnect()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() { stopping = true; serviceAlive = false; activeConnection?.disconnect(); super.onDestroy() }

    private fun transfer(item: JSONObject) {
        val id = item.getString("id")
        val target = File(item.getString("path"))
        val partial = File(target.path + ".part")
        var connection: HttpURLConnection? = null
        try {
            target.parentFile?.mkdirs()
            update(this, id) { it.put("state", "downloading").put("error", "") }
            val original = URI(item.getString("url"))
            var url = original.toURL()
            val validator = item.optString("validator")
            var offset = if (partial.exists() && validator.isNotEmpty()) partial.length() else 0L
            for (redirect in 0..6) {
                if (!isActive(id)) return
                require(url.protocol == "https" || url.protocol == "http") { "Unsupported protocol" }
                val next = url.openConnection() as HttpURLConnection
                connection = next; activeConnection = next
                next.instanceFollowRedirects = false
                next.connectTimeout = 25000; next.readTimeout = 30000
                next.setRequestProperty("User-Agent", "Mozilla/5.0 Chrome/140.0.0.0")
                next.setRequestProperty("Accept-Encoding", "identity")
                if (url.host.equals(original.host, true) && url.protocol == original.scheme) {
                    item.optString("cookie").takeIf { it.isNotEmpty() }?.let { next.setRequestProperty("Cookie", it) }
                }
                item.optString("referer").takeIf { it.isNotEmpty() }?.let { next.setRequestProperty("Referer", it) }
                if (offset > 0) { next.setRequestProperty("Range", "bytes=$offset-"); next.setRequestProperty("If-Range", validator) }
                val code = next.responseCode
                if (code in setOf(301,302,303,307,308)) {
                    require(redirect < 6) { "Too many redirects" }
                    val location = next.getHeaderField("Location") ?: error("Missing redirect location")
                    val destination = URL(url, location)
                    require(!(url.protocol == "https" && destination.protocol != "https")) { "Insecure redirect" }
                    next.disconnect(); url = destination; continue
                }
                require(code == 200 || code == 206) { "HTTP $code" }
                break
            }
            val response = connection ?: error("No response")
            val type = response.contentType.orEmpty().lowercase()
            require(!type.contains("text/html") && !type.contains("application/json")) { "Server returned a page instead of a file" }
            if (response.responseCode == 206) {
                val start = Regex("bytes (\\d+)-").find(response.getHeaderField("Content-Range").orEmpty())?.groupValues?.get(1)?.toLongOrNull()
                require(start == offset) { "Invalid resume response" }
            } else { offset = 0 }
            val length = response.getHeaderFieldLong("Content-Length", -1)
            val total = if (length >= 0) offset + length else -1
            require(length < 0 || target.parentFile!!.usableSpace > length + 1024 * 1024) { "Insufficient free space" }
            val tag = response.getHeaderField("ETag")?.takeUnless { it.startsWith("W/") } ?: response.getHeaderField("Last-Modified").orEmpty()
            update(this, id) { it.put("validator", tag).put("total", total).put("received", offset) }
            var received = offset
            var lastWrite = 0L
            RandomAccessFile(partial, "rw").use { output ->
                if (offset == 0L) output.setLength(0)
                output.seek(offset)
                response.inputStream.use { input ->
                    val buffer = ByteArray(128 * 1024)
                    while (isActive(id)) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count); received += count
                        val now = System.currentTimeMillis()
                        if (now - lastWrite > 750) {
                            lastWrite = now
                            update(this, id) { it.put("received", received) }
                            getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(item.getString("name"), total, received))
                        }
                    }
                }
                output.fd.sync()
            }
            update(this, id) { it.put("received", received) }
            if (!isActive(id)) return
            require(total < 0 || total == received) { "Incomplete response" }
            require(received > 0) { "Empty file" }
            val finalTarget = synchronized(LOCK) {
                val suggested = android.webkit.URLUtil.guessFileName(
                    response.url.toString(), response.getHeaderField("Content-Disposition"), response.contentType
                )
                if (target.extension.isEmpty() && suggested.isNotBlank()) {
                    availableTarget(target.parentFile!!, safeName(suggested), read(this), id)
                } else target
            }
            require(partial.renameTo(finalTarget)) { "Could not save file" }
            finalTarget.setLastModified(System.currentTimeMillis())
            update(this, id) {
                it.put("state", "complete").put("cookie", "").put("url", "")
                    .put("path", finalTarget.path).put("name", finalTarget.name)
            }
        } catch (error: Exception) {
            update(this, id) {
                if (it.optString("state") == "downloading") it.put("state", "failed").put("error", error.message?.take(160) ?: "Transfer failed")
            }
        } finally { connection?.disconnect(); activeConnection = null }
    }

    private fun isActive(id: String): Boolean = !stopping && synchronized(LOCK) {
        read(this).firstOrNull { it.optString("id") == id }?.optString("state") == "downloading"
    }

    private fun notification(title: String, total: Long, received: Long): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title).setContentText(getString(R.string.download_running))
            .setContentIntent(pending).setOnlyAlertOnce(true).setOngoing(true)
            .setProgress(100, if (total > 0) (received * 100 / total).toInt() else 0, total <= 0).build()
    }

    companion object {
        private val LOCK = Any()
        @Volatile private var serviceAlive = false
        private const val CHANNEL = "downloads"
        private const val NOTIFICATION = 42
        fun directory(context: Context): File = File(context.getExternalFilesDir(null) ?: context.filesDir, "Downloads").apply { mkdirs() }
        private fun read(context: Context): MutableList<JSONObject> {
            val json = JSONArray(context.getSharedPreferences("downloads", Context.MODE_PRIVATE).getString("items", "[]"))
            return (0 until json.length()).map { json.getJSONObject(it) }.toMutableList()
        }
        private fun write(context: Context, items: List<JSONObject>) {
            context.getSharedPreferences("downloads", Context.MODE_PRIVATE).edit().putString("items", JSONArray(items).toString()).commit()
        }
        private fun update(context: Context, id: String, change: (JSONObject) -> Unit) = synchronized(LOCK) {
            val items = read(context); items.firstOrNull { it.optString("id") == id }?.let(change); write(context, items)
        }
        fun tasks(context: Context): List<Map<String, Any>> = synchronized(LOCK) {
            if (!serviceAlive) recover(context)
            read(context).filterNot { it.optBoolean("hidden") }.map { item ->
                listOf("id","name","state","path","received","total","error").associateWith { key -> item.opt(key) ?: "" }
            }.reversed()
        }
        fun recover(context: Context) = synchronized(LOCK) {
            val items = read(context)
            val interrupted = items.filter { it.optString("state") == "downloading" }
            interrupted.forEach { it.put("state", "paused") }
            if (interrupted.isNotEmpty()) write(context, items)
        }
        private fun safeName(value: String): String {
            val clean = value.replace(Regex("[\\x00-\\x1f/\\\\:*?\"<>|]"), "_").trim('.', ' ').ifBlank { "download" }
            val extension = File(clean).extension.take(16)
            val suffix = if (extension.isEmpty()) "" else ".$extension"
            val stem = if (extension.isEmpty()) clean else clean.substringBeforeLast('.')
            val shortened = StringBuilder()
            for (point in stem.codePoints().toArray()) {
                val next = String(Character.toChars(point))
                if ((shortened.toString() + next + suffix).toByteArray(Charsets.UTF_8).size > 200) break
                shortened.append(next)
            }
            return shortened.toString().ifBlank { "download" } + suffix
        }
        private fun availableTarget(folder: File, name: String, items: List<JSONObject>, ownId: String = ""): File {
            var target = File(folder, name)
            var suffix = 1
            while (target.exists() || items.any { it.optString("id") != ownId && it.optString("path") == target.path }) {
                val stem = File(name).nameWithoutExtension
                val extension = File(name).extension
                target = File(folder, "$stem (${suffix++})${if (extension.isEmpty()) "" else ".$extension"}")
            }
            return target
        }
        fun enqueue(context: Context, args: Map<*, *>) = synchronized(LOCK) {
            val url = URI(args["url"] as String)
            require(url.scheme in setOf("https", "http") && url.host != null && url.userInfo == null)
            val rawName = (args["name"] as? String).orEmpty().ifBlank { "download" }
            val name = safeName(rawName)
            val folderName = (args["folder"] as? String).orEmpty().let { if (it.isBlank()) "" else safeName(it) }
            val root = directory(context)
            val folder = if (folderName.isEmpty()) root else File(root, folderName)
            folder.mkdirs()
            val items = read(context)
            val target = availableTarget(folder, name, items)
            items.add(JSONObject().put("id", UUID.randomUUID().toString()).put("name", target.name).put("path", target.path)
                .put("url", "$url").put("cookie", args["cookie"] ?: "").put("referer", args["referer"] ?: "")
                .put("state", "queued").put("received", 0).put("total", -1).put("created", System.currentTimeMillis()))
            write(context, items)
            context.startForegroundService(Intent(context, DownloadService::class.java))
        }
        fun action(context: Context, action: String, id: String) {
            update(context, id) {
                when (action) {
                    "pause" -> if (it.optString("state") in setOf("queued","downloading")) it.put("state", "paused")
                    "resume" -> if (it.optString("state") in setOf("paused","failed")) it.put("state", "queued")
                    "remove" -> if (it.optString("state") !in setOf("downloading","queued")) it.put("hidden", true)
                }
            }
            if (action == "resume") context.startForegroundService(Intent(context, DownloadService::class.java))
        }
    }
}
