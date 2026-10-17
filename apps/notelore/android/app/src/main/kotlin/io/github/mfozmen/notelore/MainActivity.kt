package io.github.mfozmen.notelore

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    /** What another app shared ("Share → Notelore"), until the Dart side takes it. */
    private var shared: Map<String, String?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) keep(intent) // not again after a restore
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        keep(intent)
    }

    private fun keep(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent?.type?.startsWith("text/") != true) return
        shared = mapOf(
            "text" to intent.getStringExtra(Intent.EXTRA_TEXT),
            "subject" to intent.getStringExtra(Intent.EXTRA_SUBJECT),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Shares (share_in.dart): asked for at start and on each return to the front.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.mfozmen.notelore/share")
            .setMethodCallHandler { call, result ->
                if (call.method == "take") {
                    result.success(shared)
                    shared = null
                } else {
                    result.notImplemented()
                }
            }
        // The in-app updater (update.dart): hands a downloaded APK to the installer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.github.mfozmen.notelore/install")
            .setMethodCallHandler { call, result ->
                if (call.method == "install") {
                    install(File(call.arguments as String), result)
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Opens Android's installer for [apk] and answers true. Answers false when installs
     * from Notelore are not allowed yet: the setting to allow them opens instead, and the
     * user taps Update again. Any failure comes back as an error for the update banner.
     */
    private fun install(apk: File, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")),
            )
            result.success(false)
            return
        }
        // Copied off the main thread into the folder the FileProvider shares
        // (res/xml/update_paths.xml); an earlier update's copy goes first.
        Thread {
            val shared = runCatching {
                val folder = File(cacheDir, "updates").apply { deleteRecursively(); mkdirs() }
                apk.copyTo(folder.resolve(apk.name), overwrite = true)
            }
            runOnUiThread {
                try {
                    val uri = FileProvider.getUriForFile(this, "$packageName.updates", shared.getOrThrow())
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                } catch (error: Exception) {
                    result.error("install_failed", error.message, null)
                }
            }
        }.start()
    }
}
