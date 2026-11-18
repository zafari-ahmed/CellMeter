package com.cellmeter.app.monitor

import android.content.Context
import android.util.Log
import com.cellmeter.app.battery.BatterySnapshot
import java.io.File
import java.io.RandomAccessFile

/**
 * Durable hand-off of samples from the native sampler to the Flutter side.
 *
 * The sampler and the Flutter database never touch the same SQLite file. The
 * service only ever appends newline-delimited JSON to [spoolFile]; Dart reads
 * whole lines, writes them into drift, and then calls [consumeThrough] to drop
 * what it has ingested. An append-only file makes the hot path trivially
 * correct — no locking, no schema shared across two languages, and a process
 * kill mid-write costs at most the final partial line, which the reader skips.
 *
 * Size is bounded by [MAX_BYTES]. If the user never opens the app, the oldest
 * half of the spool is discarded rather than letting it grow without limit.
 */
class SampleSink(context: Context) {

    private val appContext = context.applicationContext
    private val lock = Any()

    val spoolFile: File
        get() = File(appContext.filesDir, SPOOL_NAME)

    fun append(snapshot: BatterySnapshot) {
        val line = snapshot.toJson().toString()
        synchronized(lock) {
            try {
                val file = spoolFile
                file.parentFile?.mkdirs()
                file.appendText(line + "\n")
                if (file.length() > MAX_BYTES) trimOldestLocked(file)
            } catch (t: Throwable) {
                Log.w(TAG, "Failed to spool sample", t)
            }
        }
    }

    /** Current spool size in bytes; surfaced in the diagnostics screen. */
    fun sizeBytes(): Long = synchronized(lock) {
        val file = spoolFile
        if (file.exists()) file.length() else 0L
    }

    /**
     * Drops the first [lineCount] lines, which the Dart side has just committed
     * to the database. Called after a successful ingest, never before.
     */
    fun consumeThrough(lineCount: Int): Int {
        if (lineCount <= 0) return 0
        return synchronized(lock) {
            val file = spoolFile
            if (!file.exists()) return@synchronized 0
            try {
                val remaining = file.useLines { lines -> lines.drop(lineCount).toList() }
                if (remaining.isEmpty()) {
                    file.delete()
                } else {
                    file.writeText(remaining.joinToString("\n", postfix = "\n"))
                }
                lineCount
            } catch (t: Throwable) {
                Log.w(TAG, "Failed to consume spool", t)
                0
            }
        }
    }

    fun clear() = synchronized(lock) {
        runCatching { spoolFile.delete() }
        Unit
    }

    /**
     * Keeps the newest half of the file. Truncating from the front needs a
     * rewrite either way, so the simplest correct form is to read the tail and
     * write it back.
     */
    private fun trimOldestLocked(file: File) {
        try {
            val keepFrom = file.length() / 2
            val tail = RandomAccessFile(file, "r").use { raf ->
                raf.seek(keepFrom)
                raf.readLine() // discard the partial line we landed in
                buildString {
                    while (true) {
                        val line = raf.readLine() ?: break
                        append(line).append('\n')
                    }
                }
            }
            file.writeText(tail)
            Log.i(TAG, "Spool trimmed to ${file.length()} bytes")
        } catch (t: Throwable) {
            Log.w(TAG, "Trim failed, clearing spool", t)
            runCatching { file.delete() }
        }
    }

    private companion object {
        const val TAG = "CellMeter/Sink"
        const val SPOOL_NAME = "battery_spool.jsonl"

        /** ~5 MB holds roughly two weeks of sampling at the default cadence. */
        const val MAX_BYTES = 5L * 1024 * 1024
    }
}
