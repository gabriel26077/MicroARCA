package com.microarca.app

import android.os.Handler
import android.os.SystemClock

/** Aguarda o registro assíncrono do CDM, sem bloquear a interface. */
internal class AssociationConfirmation(
    private val handler: Handler,
    private val isAssociated: () -> Boolean,
    private val onConfirmed: () -> Unit,
    private val onTimeout: () -> Unit,
    private val onError: (Exception) -> Unit,
    private val timeoutMs: Long = 3000,
    private val intervalMs: Long = 150,
) {
    private var started = false
    private var active = false
    private var deadline = 0L
    private val check = object : Runnable {
        override fun run() {
            if (!active) return
            val confirmed = try {
                isAssociated()
            } catch (error: Exception) {
                cancel()
                onError(error)
                return
            }
            if (confirmed) {
                cancel()
                onConfirmed()
            } else {
                val remaining = deadline - SystemClock.uptimeMillis()
                if (remaining <= 0) {
                    cancel()
                    onTimeout()
                } else {
                    handler.postDelayed(this, minOf(intervalMs, remaining))
                }
            }
        }
    }

    fun start() {
        if (started) return
        started = true
        active = true
        deadline = SystemClock.uptimeMillis() + timeoutMs
        check.run()
    }

    fun cancel() {
        active = false
        handler.removeCallbacks(check)
    }
}
