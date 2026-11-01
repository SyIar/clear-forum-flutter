package dev.sylar.tablet.forum_tablet

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.sylar.tablet/downloads").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "directory" -> result.success(DownloadService.directory(this).path)
                    "tasks" -> result.success(DownloadService.tasks(this))
                    "fileJobStatus" -> result.success(LocalFileTools.status())
                    "startFileJob" -> result.success(LocalFileTools.start(this,
                        call.argument<String>("operation")!!, call.argument<String>("path")!!, call.argument<String>("password")))
                    "resolvePath" -> result.success(LocalFileTools.resolved(this, call.argument<String>("path")!!))
                    "canDelete" -> {
                        val file = LocalFileTools.checked(DownloadService.directory(this), File(call.argument<String>("path")!!))
                        result.success(!LocalFileTools.busy(file.path) && !DownloadService.busyPath(this, file.path))
                    }
                    "refreshLink" -> { DownloadService.refreshLink(this, call.arguments as Map<*, *>); result.success(null) }
                    "enqueue" -> {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42)
                        }
                        DownloadService.enqueue(this, call.arguments as Map<*, *>); result.success(null)
                    }
                    "pause", "resume", "remove", "resolutionFailed" -> {
                        DownloadService.action(this, call.method, call.argument<String>("id")!!); result.success(null)
                    }
                    "openFile" -> {
                        val file = LocalFileTools.checked(DownloadService.directory(this),
                            File(LocalFileTools.resolved(this, call.argument<String>("path")!!)))
                        require(file.path.startsWith(DownloadService.directory(this).canonicalPath + File.separator))
                        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                        val mime = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"
                        startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), null))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("download_error", error.message, null) }
        }
    }
}
