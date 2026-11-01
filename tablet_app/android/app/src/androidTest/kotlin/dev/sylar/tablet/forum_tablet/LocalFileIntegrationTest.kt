package dev.sylar.tablet.forum_tablet

import android.content.Context
import android.graphics.BitmapFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import net.lingala.zip4j.ZipFile
import net.lingala.zip4j.model.ZipParameters
import net.lingala.zip4j.model.enums.EncryptionMethod
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.util.UUID
import java.util.zip.CRC32
import java.util.zip.Deflater
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Runs on an Android emulator in CI against Android Bitmap and real private storage. */
@RunWith(AndroidJUnit4::class)
class LocalFileIntegrationTest {
    private lateinit var context: Context
    private lateinit var root: File
    @Before fun prepare() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        root = File(DownloadService.directory(context), "integration-${UUID.randomUUID()}").apply { mkdirs() }
    }
    @After fun clean() {
        check(root.canonicalPath.startsWith(DownloadService.directory(context).canonicalPath + File.separator))
        check(root.name.startsWith("integration-"))
        root.deleteRecursively()
    }

    @Test fun encryptedZipAndStandardZipExtractWithoutReplacingExistingFiles() {
        for (encryption in listOf(EncryptionMethod.AES, EncryptionMethod.ZIP_STANDARD, EncryptionMethod.NONE)) {
            val archive = File(root, "sample-${encryption.name}.zip")
            val bytes = ByteArray(32768) { (it % 251).toByte() }
            val password = "private-test-password".toCharArray()
            ZipFile(archive, password).use { zip ->
                val parameters = ZipParameters().apply {
                    fileNameInZip = "nested/payload.bin"
                    isEncryptFiles = encryption != EncryptionMethod.NONE
                    encryptionMethod = encryption
                }
                zip.addStream(bytes.inputStream(), parameters)
            }
            val first = LocalFileTools.extract(root, archive, password)
            val second = LocalFileTools.extract(root, archive, password)
            assertNotEquals(first.path, second.path)
            assertArrayEquals(bytes, File(first, "nested/payload.bin").readBytes())
            assertArrayEquals(bytes, File(second, "nested/payload.bin").readBytes())
            assertTrue(archive.exists())
            assertFalse(root.listFiles()!!.any { it.name.startsWith(".forum-extract-") })
        }
    }

    @Test fun wrongPasswordPublishesNoPartialDirectory() {
        val archive = File(root, "encrypted.zip")
        ZipFile(archive, "correct".toCharArray()).use { zip ->
            zip.addStream(ByteArray(2048) { 42 }.inputStream(), ZipParameters().apply {
                fileNameInZip = "payload.bin"; isEncryptFiles = true; encryptionMethod = EncryptionMethod.AES
            })
        }
        for (password in listOf(null, "wrong".toCharArray())) {
            try { LocalFileTools.extract(root, archive, password); fail("Expected password failure") }
            catch (_: Exception) { }
            assertEquals(listOf(archive.name), root.listFiles()!!.map { it.name })
        }
    }

    @Test fun unsafeArchiveEntriesCannotEscapeStaging() {
        for (name in listOf("../escaped.txt", "/absolute.txt", "folder/../../escape.txt", "C:/escape.txt")) {
            val archive = File(root, "unsafe.zip")
            ZipOutputStream(archive.outputStream()).use { zip ->
                zip.putNextEntry(ZipEntry(name)); zip.write(byteArrayOf(1, 2, 3)); zip.closeEntry()
            }
            try { LocalFileTools.extract(root, archive, null); fail("Expected path rejection") }
            catch (_: FileToolFailure) { }
            assertEquals(listOf(archive.name), root.listFiles()!!.map { it.name })
        }
    }

    @Test fun losslessConversionPreservesPixelsArrivalAndOldPathResolution() {
        val png = File(root, "picture.png").apply { writeBytes(pngBytes()) }
        val size = png.length()
        val arrival = System.currentTimeMillis() - 60000
        png.setLastModified(arrival)
        val bitmap = BitmapFactory.decodeFile(png.path)
        val expected = IntArray(128 * 128)
        bitmap.getPixels(expected, 0, 128, 0, 0, 128, 128); bitmap.recycle()
        val result = LocalFileTools.convert(context, root, png)
        assertNotNull("Opaque sRGB PNG should convert", result)
        val webp = result!!.first
        assertTrue(webp.length() < size)
        assertFalse(png.exists())
        assertEquals(arrival, webp.lastModified())
        assertEquals(webp.path, LocalFileTools.resolved(context, png.path))
        val restored = BitmapFactory.decodeFile(webp.path)
        val actual = IntArray(128 * 128)
        restored.getPixels(actual, 0, 128, 0, 0, 128, 128); restored.recycle()
        assertArrayEquals(expected, actual)
    }

    @Test fun transparencyMetadataAndExistingOutputKeepOriginalsIntact() {
        for ((name, bytes) in listOf("transparent" to pngBytes(alpha = true), "metadata" to pngBytes(metadata = true))) {
            val png = File(root, "$name.png").apply { writeBytes(bytes) }
            assertNull(LocalFileTools.convert(context, root, png))
            assertArrayEquals(bytes, png.readBytes())
            assertFalse(File(root, "$name.webp").exists())
        }
        val png = File(root, "collision.png").apply { writeBytes(pngBytes()) }
        val existing = File(root, "collision.webp").apply { writeText("existing-content") }
        val before = png.readBytes()
        assertNull(LocalFileTools.convert(context, root, png))
        assertArrayEquals(before, png.readBytes())
        assertEquals("existing-content", existing.readText())
    }

    @Test fun convertedOutputProvenanceNeverDeletesAnUnrelatedReplacement() {
        val bytes = pngBytes()
        val png = File(root, "recovery.png").apply { writeBytes(bytes) }
        val output = LocalFileTools.convert(context, root, png)!!.first
        // Simulate a process stopping after the journal commit, before original deletion.
        png.writeBytes(bytes)
        assertNotNull(LocalFileTools.convert(context, root, png))
        assertFalse(png.exists())
        png.writeBytes(bytes)
        output.writeText("another-file")
        assertNull(LocalFileTools.convert(context, root, png))
        assertArrayEquals(bytes, png.readBytes())
        assertEquals("another-file", output.readText())
    }

    private fun pngBytes(alpha: Boolean = false, metadata: Boolean = false): ByteArray {
        val result = ByteArrayOutputStream()
        val out = DataOutputStream(result)
        out.write(byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10))
        fun chunk(type: String, bytes: ByteArray) {
            val name = type.toByteArray(Charsets.US_ASCII)
            out.writeInt(bytes.size); out.write(name); out.write(bytes)
            val crc = CRC32().apply { update(name); update(bytes) }; out.writeInt(crc.value.toInt())
        }
        val header = ByteArrayOutputStream()
        DataOutputStream(header).use { it.writeInt(128); it.writeInt(128); it.write(byteArrayOf(8, if (alpha) 6 else 2, 0, 0, 0)) }
        chunk("IHDR", header.toByteArray()); chunk("sRGB", byteArrayOf(0))
        if (metadata) chunk("tEXt", "Comment\u0000keep-me".toByteArray(Charsets.US_ASCII))
        val pixels = ByteArrayOutputStream()
        for (y in 0 until 128) {
            pixels.write(0)
            for (x in 0 until 128) { pixels.write(x); pixels.write(y); pixels.write(128); if (alpha) pixels.write(128) }
        }
        val compressed = ByteArrayOutputStream()
        DeflaterOutputStream(compressed, Deflater(0)).use { it.write(pixels.toByteArray()) }
        chunk("IDAT", compressed.toByteArray()); chunk("IEND", byteArrayOf())
        return result.toByteArray()
    }
}
