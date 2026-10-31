package kr.ruellyya.keepfall.updater

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.io.File
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Installs an update APK the game already downloaded and checked (SHA-256) through a PackageInstaller
 * session, so the player confirms one system dialog instead of finding the file in a browser. Android only
 * installs it when it is signed with the same key as the running app.
 */
class KeepfallUpdater(godot: Godot) : GodotPlugin(godot) {
    private var receiver: BroadcastReceiver? = null

    override fun getPluginName() = "KeepfallUpdater"

    /** install_status(state, detail): "confirm" (the system dialog is up), "installed", "failed", "cancelled". */
    override fun getPluginSignals() = setOf(SignalInfo("install_status", String::class.java, String::class.java))

    /** Whether the player already let this app install updates (always true before Android 8). */
    @UsedByGodot
    fun canInstall(): Boolean {
        val activity = activity ?: return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity.packageManager.canRequestPackageInstalls()
    }

    /** Opens the "install unknown apps" setting for this app. */
    @UsedByGodot
    fun openInstallSettings() {
        val activity = activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activity.packageName)))
        }
    }

    /** Streams the APK at [path] (an absolute file path) into an install session and asks the system to install it. */
    @UsedByGodot
    fun installApk(path: String) {
        val activity = activity
        if (activity == null) {
            report("failed", "no_activity")
            return
        }
        Thread {
            try {
                val file = File(path)
                val installer = activity.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                params.setAppPackageName(activity.packageName)
                params.setSize(file.length())
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("update.apk", 0, file.length()).use { output ->
                            input.copyTo(output)
                            session.fsync(output)
                        }
                    }
                    listen(activity)
                    val intent = Intent(ACTION).setPackage(activity.packageName)
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                    session.commit(PendingIntent.getBroadcast(activity, sessionId, intent, flags).intentSender)
                }
            } catch (error: Exception) {
                report("failed", error.message ?: error.javaClass.simpleName)
            }
        }.start()
    }

    private fun listen(context: Context) {
        if (receiver != null) return
        val created = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                    PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                        @Suppress("DEPRECATION")
                        val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java) else intent.getParcelableExtra(Intent.EXTRA_INTENT)
                        if (confirm == null) {
                            report("failed", "no_confirmation")
                        } else {
                            confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            (activity ?: context).startActivity(confirm)
                            report("confirm", "")
                        }
                    }
                    PackageInstaller.STATUS_SUCCESS -> report("installed", "")
                    PackageInstaller.STATUS_FAILURE_ABORTED -> report("cancelled", "")
                    else -> report("failed", "$status " + (intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""))
                }
            }
        }
        val filter = IntentFilter(ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.applicationContext.registerReceiver(created, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.applicationContext.registerReceiver(created, filter)
        }
        receiver = created
    }

    private fun report(state: String, detail: String) {
        runOnRenderThread { emitSignal("install_status", state, detail.take(200)) }
    }

    companion object {
        private const val ACTION = "kr.ruellyya.keepfall.updater.INSTALL_STATUS"
    }
}
