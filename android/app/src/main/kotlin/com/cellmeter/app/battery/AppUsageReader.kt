package com.cellmeter.app.battery

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Process
import android.provider.Settings
import android.util.Log

/**
 * Foreground time per app, which is what makes per-app battery attribution
 * possible.
 *
 * Android does not expose a per-app energy figure that is worth showing. The
 * platform's own numbers come from `power_profile.xml` — a table of nominal
 * component costs supplied by the OEM — multiplied by estimated usage, and on
 * real hardware those tables are frequently wrong by large margins.
 *
 * CellMeter instead measures the one thing it can measure exactly, the total
 * charge the battery actually lost (from the coulomb counter), and divides it
 * across apps in proportion to the time each spent in the foreground over the
 * same window. That yields "this app was on screen for the slice of your day
 * that cost you 340 mAh", which is a claim the data supports, rather than a
 * fabricated per-app wattage.
 *
 * Requires the user to grant Usage Access in system settings. It cannot be
 * requested from a dialog, so the app has to send them there.
 */
class AppUsageReader(context: Context) {

    private val appContext = context.applicationContext
    private val packageManager: PackageManager = appContext.packageManager

    private val usageStatsManager: UsageStatsManager? =
        appContext.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager

    /** Cheap label cache; resolving an app label hits the package manager. */
    private val labelCache = HashMap<String, String>()

    data class ForegroundSlice(
        val packageName: String,
        val label: String,
        val foregroundMs: Long,
        val isSystemApp: Boolean,
        val isLauncher: Boolean,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "packageName" to packageName,
            "label" to label,
            "foregroundMs" to foregroundMs,
            "isSystemApp" to isSystemApp,
            "isLauncher" to isLauncher,
        )
    }

    /**
     * The package currently handling the home screen.
     *
     * Flagged separately from [isSystemApp] because the launcher is a
     * different kind of entry altogether: its foreground time is the seams
     * between apps — every swipe home, every app switch — rather than
     * something the user chose to do, and it therefore tops the list on almost
     * every device. Resolved through the HOME intent rather than matched
     * against a package name, so a third-party launcher is treated the same
     * way as the stock one.
     */
    private val launcherPackage: String? by lazy {
        try {
            packageManager.resolveActivity(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
                PackageManager.MATCH_DEFAULT_ONLY,
            )?.activityInfo?.packageName
        } catch (_: Throwable) {
            null
        }
    }

    fun hasUsageAccess(): Boolean {
        val appOps = appContext.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return false
        return try {
            val mode = appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                appContext.packageName,
            )
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Throwable) {
            false
        }
    }

    fun usageAccessSettingsIntent(): Intent =
        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }

    /**
     * Foreground milliseconds per package between [startMs] and [endMs].
     *
     * Built from the raw event stream rather than from `queryUsageStats`,
     * because the aggregated buckets are snapped to day boundaries and cannot
     * answer "during this one charge session". Events give exact transitions.
     *
     * An app that was already in the foreground when the window opened is
     * credited from the window start; one still in the foreground at the end is
     * credited to the window end.
     */
    fun foregroundSlices(startMs: Long, endMs: Long): List<ForegroundSlice> {
        val manager = usageStatsManager ?: return emptyList()
        if (!hasUsageAccess()) return emptyList()
        if (endMs <= startMs) return emptyList()

        return try {
            val totals = HashMap<String, Long>()
            val openedAt = HashMap<String, Long>()

            // Query from a little before the window so a session that began
            // earlier is caught by its resume event.
            val events = manager.queryEvents(startMs - LOOKBEHIND_MS, endMs)
            val event = UsageEvents.Event()

            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                val pkg = event.packageName ?: continue
                when (event.eventType) {
                    UsageEvents.Event.ACTIVITY_RESUMED ->
                        openedAt[pkg] = event.timeStamp
                    UsageEvents.Event.ACTIVITY_PAUSED,
                    UsageEvents.Event.ACTIVITY_STOPPED -> {
                        val start = openedAt.remove(pkg) ?: continue
                        addClamped(totals, pkg, start, event.timeStamp, startMs, endMs)
                    }
                }
            }

            // Whatever is still open ran until the end of the window.
            for ((pkg, start) in openedAt) {
                addClamped(totals, pkg, start, endMs, startMs, endMs)
            }

            totals.entries
                .filter { it.value >= MIN_SLICE_MS }
                .map { (pkg, ms) ->
                    ForegroundSlice(
                        packageName = pkg,
                        label = labelFor(pkg),
                        foregroundMs = ms,
                        isSystemApp = isSystemApp(pkg),
                        isLauncher = pkg == launcherPackage,
                    )
                }
                .sortedByDescending { it.foregroundMs }
        } catch (t: Throwable) {
            Log.w(TAG, "Usage query failed", t)
            emptyList()
        }
    }

    /** Adds an interval to a package's total, clipped to the window. */
    private fun addClamped(
        totals: HashMap<String, Long>,
        pkg: String,
        from: Long,
        to: Long,
        windowStart: Long,
        windowEnd: Long,
    ) {
        val start = maxOf(from, windowStart)
        val end = minOf(to, windowEnd)
        if (end <= start) return
        totals[pkg] = (totals[pkg] ?: 0L) + (end - start)
    }

    private fun labelFor(packageName: String): String =
        labelCache.getOrPut(packageName) {
            try {
                val info = packageManager.getApplicationInfo(packageName, 0)
                packageManager.getApplicationLabel(info).toString()
            } catch (_: Throwable) {
                packageName
            }
        }

    private fun isSystemApp(packageName: String): Boolean = try {
        val info = packageManager.getApplicationInfo(packageName, 0)
        (info.flags and (ApplicationInfo.FLAG_SYSTEM or
            ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0
    } catch (_: Throwable) {
        false
    }

    private companion object {
        const val TAG = "CellMeter/Usage"
        const val LOOKBEHIND_MS = 12 * 60 * 60 * 1000L
        /** Below two seconds a foreground slice is a transition, not usage. */
        const val MIN_SLICE_MS = 2_000L
    }
}
