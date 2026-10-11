package io.github.mfozmen.notelore

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The in-app updater (update.dart): hands a downloaded APK to the installer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.mfozmen.notelore/install")
            .setMethodCallHandler { call, result ->
                if (call.method == "install") {
                    result.success(install(File(call.arguments as String)))
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Opens Android's installer for [apk]. False when installs from Notelore are not
     * allowed yet: the setting to allow them opens instead, and the user taps Update again.
     */
    private fun install(apk: File): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")),
            )
            return false
        }
        // Shared from the cache through the FileProvider (res/xml/update_paths.xml).
        val shared = File(cacheDir, "updates").apply { mkdirs() }.resolve(apk.name)
        apk.copyTo(shared, overwrite = true)
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", shared)
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        return true
    }
}
