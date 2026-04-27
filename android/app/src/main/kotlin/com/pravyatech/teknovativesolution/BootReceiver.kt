package com.pravyatech.teknovativesolution

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (
            action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }

        val trackingEnabled = context
            .getSharedPreferences("ServicePrefs", Context.MODE_PRIVATE)
            .getBoolean("tracking_enabled", false)

        if (!trackingEnabled) {
            Log.d("BootReceiver", "Tracking disabled, skipping restart on $action")
            return
        }

        try {
            val startIntent = Intent(context, MyForegroundService::class.java).apply {
                this.action = MyForegroundService.ACTION_START_SERVICE
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(startIntent)
            } else {
                context.startService(startIntent)
            }
            Log.d("BootReceiver", "Tracking service restart requested on $action")
        } catch (e: Exception) {
            Log.e("BootReceiver", "Failed to restart service on $action: ${e.message}")
        }
    }
}
