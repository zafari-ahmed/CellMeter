package com.cellmeter.app.battery

import java.io.File

/**
 * Best-effort reads of the kernel power-supply nodes.
 *
 * On most devices released after Android 9 these paths are blocked for normal
 * apps by SELinux, so every read here is expected to fail and every caller must
 * treat `null` as the normal case. When they do succeed — typically on older or
 * more permissive devices — they are the only source of true design capacity
 * and cycle count, which makes them worth attempting once.
 */
object SysfsBattery {

    private val SUPPLY_ROOTS = listOf(
        "/sys/class/power_supply/battery",
        "/sys/class/power_supply/bms",
        "/sys/class/power_supply/Battery",
    )

    /** Full-charge capacity as the gauge currently believes it to be, in mAh. */
    fun chargeFullMah(): Int? = readCapacityNode("charge_full")

    /** Factory design capacity, in mAh. */
    fun chargeFullDesignMah(): Int? = readCapacityNode("charge_full_design")

    /** Completed charge cycles as counted by the gauge. */
    fun cycleCount(): Int? {
        val raw = readFirst("cycle_count")?.toIntOrNull() ?: return null
        return if (raw in 1..10_000) raw else null
    }

    /**
     * Capacity nodes are reported in microamp-hours on most kernels and in
     * milliamp-hours on some. Anything under 100_000 is read as mAh.
     */
    private fun readCapacityNode(name: String): Int? {
        val raw = readFirst(name)?.toLongOrNull() ?: return null
        if (raw <= 0) return null
        val mah = if (raw >= 100_000L) (raw / 1000L).toInt() else raw.toInt()
        return if (mah in 300..30_000) mah else null
    }

    private fun readFirst(name: String): String? {
        for (root in SUPPLY_ROOTS) {
            val value = readNode(File(root, name))
            if (value != null) return value
        }
        return null
    }

    private fun readNode(file: File): String? = try {
        if (file.canRead()) file.readText().trim().ifEmpty { null } else null
    } catch (_: Throwable) {
        null
    }
}
