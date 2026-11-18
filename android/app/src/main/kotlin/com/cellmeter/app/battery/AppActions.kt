package com.cellmeter.app.battery

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.provider.Settings
import android.util.Base64
import java.io.ByteArrayOutputStream

/**
 * What CellMeter can actually do about an app that is using battery.
 *
 * Deliberately short, because Android deliberately makes it short:
 *
 * Force-stopping another app needs `android.permission.FORCE_STOP_PACKAGES`,
 * which is signature-level and unavailable to anything not signed with the
 * platform key. The one public alternative,
 * `ActivityManager.killBackgroundProcesses`, only drops background processes
 * the system then restarts at will — it reliably appears to work and reliably
 * changes nothing, which is worse than offering nothing. Play also treats
 * task-killer behaviour as a negative signal, and rightly: the platform's own
 * process management is better at this than an app guessing from the outside.
 *
 * So CellMeter does not pretend to kill anything. It puts the user one tap
 * from the system screens that genuinely can — Force stop and the background
 * restriction toggle both live in the app's details page — and is explicit
 * about which of them is doing the work.
 */
class AppActions(context: Context) {

    private val appContext = context.applicationContext
    private val packageManager = appContext.packageManager

    /**
     * Opens the system details page for [packageName], where Force stop,
     * battery restriction and notification settings live.
     */
    fun openAppSettings(packageName: String): Boolean = start(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", packageName, null)),
    )

    /** Launches the app itself. */
    fun launchApp(packageName: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: return false
        return start(intent)
    }

    /**
     * Asks the system to uninstall [packageName]. The user confirms in the
     * system dialog; nothing is removed on CellMeter's say-so.
     */
    fun requestUninstall(packageName: String): Boolean = start(
        Intent(Intent.ACTION_DELETE)
            .setData(Uri.fromParts("package", packageName, null)),
    )

    /** Whether this package can be uninstalled, i.e. is not a system app. */
    fun canUninstall(packageName: String): Boolean = try {
        val info = packageManager.getApplicationInfo(packageName, 0)
        val system = (info.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
        !system && packageName != appContext.packageName
    } catch (_: Throwable) {
        false
    }

    fun hasLaunchIntent(packageName: String): Boolean =
        packageManager.getLaunchIntentForPackage(packageName) != null

    /**
     * The app's icon as a base64 PNG, for the usage list.
     *
     * Rendered at a fixed small size rather than passed through at whatever
     * density the device stores: these cross a method-channel reply in bulk,
     * and a dozen full-resolution adaptive icons would be megabytes.
     */
    fun iconPng(packageName: String, sizePx: Int = 96): String? = try {
        val drawable = packageManager.getApplicationIcon(packageName)
        val bitmap = drawable.toBitmap(sizePx)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    } catch (_: Throwable) {
        null
    }

    private fun Drawable.toBitmap(size: Int): Bitmap {
        if (this is BitmapDrawable && bitmap != null) {
            return Bitmap.createScaledBitmap(bitmap, size, size, true)
        }
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        setBounds(0, 0, size, size)
        draw(canvas)
        return bitmap
    }

    private fun start(intent: Intent): Boolean = try {
        appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Throwable) {
        false
    }
}
