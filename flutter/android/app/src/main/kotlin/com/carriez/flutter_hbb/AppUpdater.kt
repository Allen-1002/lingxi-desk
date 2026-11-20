package com.carriez.flutter_hbb

// Lingxi Desk: installs an APK downloaded by the in-app updater
// (flutter/lib/lingxi/lingxi_update.dart) through the system installer.

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import java.io.File

object AppUpdater {
    private const val TAG = "LingxiUpdater"

    fun canInstall(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < 26 || ctx.packageManager.canRequestPackageInstalls()

    fun openInstallPermission(ctx: Context) {
        ctx.startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    /** Returns null when the installer was started, otherwise a message for the user. */
    fun install(ctx: Context, path: String): String? {
        val apk = runCatching { File(path).canonicalFile }.getOrNull() ?: return "找不到安装包"
        val allowed = runCatching { File(ctx.cacheDir, "updates").canonicalFile }.getOrNull()
        if (allowed == null || apk.parentFile != allowed || !apk.name.endsWith(".apk") || !apk.isFile) {
            return "安装包位置不对"
        }
        return try {
            val installer = ctx.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(ctx.packageName)
            if (Build.VERSION.SDK_INT >= 31) {
                params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
            }
            val id = installer.createSession(params)
            installer.openSession(id).use { s ->
                apk.inputStream().use { ins ->
                    s.openWrite("base.apk", 0, apk.length()).use { out ->
                        ins.copyTo(out)
                        s.fsync(out)
                    }
                }
                val intent = Intent(ctx, InstallResultReceiver::class.java)
                    .setAction(InstallResultReceiver.ACTION)
                    .setPackage(ctx.packageName)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                s.commit(PendingIntent.getBroadcast(ctx, id, intent, flags).intentSender)
            }
            null
        } catch (e: Exception) {
            Log.e(TAG, "install failed", e)
            "无法打开系统安装器：${e.message}"
        }
    }
}

/** Result of the PackageInstaller session: shows the confirm screen when the system asks for it. */
class InstallResultReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION = "com.lingxi.desk.INSTALL_RESULT"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirm = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            }
            confirm?.let { context.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        } else if (status != PackageInstaller.STATUS_SUCCESS) {
            Log.w("LingxiUpdater", "install status $status: ${intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)}")
        }
    }
}
