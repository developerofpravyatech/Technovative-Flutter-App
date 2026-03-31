package com.pravyatech.teknovativesolution

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.pravyatech.teknovativesolution.R


class UploadAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        Log.e("UploadAlarmReceiver", "⏰ Alarm triggered. Uploading locations.")
        
        // Check if GPS is enabled
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
        val isGpsEnabled = locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)
        if (!isGpsEnabled) {
            // Fire local notification
            val channelId = "ApiCallChannel"
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val channel = android.app.NotificationChannel(
                    channelId,
                    "API Call Notifications",
                    android.app.NotificationManager.IMPORTANCE_HIGH
                )
                notificationManager.createNotificationChannel(channel)
            }
            val notification = androidx.core.app.NotificationCompat.Builder(context, channelId)
                .setContentTitle("GPS is OFF")
                .setContentText("Please enable GPS for location tracking.")
                .setSmallIcon(R.mipmap.launcher_icon)
                .setAutoCancel(true)
                .build()
            val notificationId = (System.currentTimeMillis() % 10000).toInt()
            notificationManager.notify(notificationId, notification)

            // Call API to inform server
            val sharedPref = context.getSharedPreferences("UserDataPrefs", android.content.Context.MODE_PRIVATE)
            val userId = sharedPref.getString("user_id", null)
            val hostUrl = sharedPref.getString("url", null)
            if (!userId.isNullOrEmpty() && !hostUrl.isNullOrEmpty()) {
                Thread {
                    try {
                        val payload = org.json.JSONObject()
                        payload.put("user_id", userId)
                        payload.put("internet_status", "true")
                        payload.put("gps_status", "true")
                        payload.put("timestamp", java.text.SimpleDateFormat("dd-MM-yyyy HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date()))
                        android.util.Log.d("UploadAlarmReceiver", "📤 GPS status payload: $payload")
                        val url = java.net.URL(hostUrl)
                        val conn = url.openConnection() as java.net.HttpURLConnection
                        conn.requestMethod = "POST"
                        conn.setRequestProperty("Content-Type", "application/json")
                        conn.doOutput = true
                        val outputWriter = conn.outputStream.bufferedWriter()
                        outputWriter.write(payload.toString())
                        outputWriter.flush()
                        outputWriter.close()
                        val responseCode = conn.responseCode
                        android.util.Log.d("UploadAlarmReceiver", "GPS API response code: $responseCode")
                        android.util.Log.d("UploadAlarmReceiver", "✅ GPS disabled sent. Response code: $responseCode")
                        conn.disconnect()
                    } catch (e: Exception) {
                        android.util.Log.e("UploadAlarmReceiver", "❌ Failed to send GPS disabled: ${e.message}")
                    }
                }.start()
            } else {
                android.util.Log.e("UploadAlarmReceiver", "❌ User ID or URL missing for GPS disabled API call")
            }
        }
        
        MyForegroundService.sendLocationsToServerStatic(context)
        MyForegroundService.scheduleUploadWithAlarm(context) // Schedule next run
    }
}