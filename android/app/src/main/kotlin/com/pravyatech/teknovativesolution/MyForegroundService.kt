package com.pravyatech.teknovativesolution

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Binder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.pravyatech.teknovativesolution.R
import org.json.JSONObject
import java.io.BufferedWriter
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.*

class MyForegroundService : Service() {
    private val binder = LocalBinder()
    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val CHANNEL_ID = "LocationTrackingChannel"
    private val NOTIFICATION_ID = 1001
    private var isServiceRunning = false
    private var lastLocation: Location? = null
    private var userId: String? = null
    private var apiUrl: String? = null
    private var timeFilter: Long = 60000 // Default 1 minute
    private var distanceFilter: Float = 10f // Default 10 meters
    private var alarmManager: AlarmManager? = null
    private var pendingIntent: android.app.PendingIntent? = null
    private val prefsName = "ServicePrefs"
    private val trackingEnabledKey = "tracking_enabled"
    private val uploadHandler = Handler(Looper.getMainLooper())
    private val uploadRunnable = object : Runnable {
        override fun run() {
            if (!isServiceRunning || !isTrackingEnabled()) return
            try {
                sendLocationsToServer()
            } catch (e: Exception) {
                Log.e(TAG, "Heartbeat upload failed: ${e.message}")
            } finally {
                uploadHandler.postDelayed(this, UPLOAD_INTERVAL_MS)
            }
        }
    }

    inner class LocalBinder : Binder() {
        fun getService(): MyForegroundService = this@MyForegroundService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        createNotificationChannel()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        acquireWakeLock()
        loadPreferences()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service onStartCommand action=${intent?.action}")
        when (intent?.action) {
            ACTION_START_SERVICE -> {
                setTrackingEnabled(true)
                startForegroundService()
            }
            ACTION_STOP_SERVICE -> {
                setTrackingEnabled(false)
                stopForegroundService()
            }
            null -> {
                // System may restart sticky services with null intent.
                if (isTrackingEnabled()) {
                    Log.d(TAG, "Null intent restart detected, restoring foreground tracking")
                    startForegroundService()
                } else {
                    Log.d(TAG, "Null intent restart but tracking not enabled, not restarting")
                }
            }
            else -> {
                if (isTrackingEnabled()) {
                    Log.d(TAG, "Unknown action but tracking enabled, restoring foreground tracking")
                    startForegroundService()
                }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service onDestroy")
        stopLocationUpdates()
        stopUploadHeartbeat()
        releaseWakeLock()
        cancelAlarm()
        isServiceRunning = false
        if (isTrackingEnabled()) {
            Log.w(TAG, "Service destroyed while tracking enabled; scheduling restart")
            scheduleServiceRestart(this, 10_000L)
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.w(TAG, "onTaskRemoved called")
        if (isTrackingEnabled()) {
            scheduleServiceRestart(this, 5_000L)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Location Tracking Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Tracks your location in the background"
                setShowBadge(false)
            }
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundService() {
        if (isServiceRunning) {
            Log.d(TAG, "Service already running")
            startUploadHeartbeat()
            return
        }

        val notification = createNotification("Location tracking is active")
        startForeground(NOTIFICATION_ID, notification)
        startLocationUpdates()
        scheduleUploadWithAlarm(this)
        startUploadHeartbeat()
        isServiceRunning = true
        Log.d(TAG, "Foreground service started")
    }

    private fun stopForegroundService() {
        stopLocationUpdates()
        stopUploadHeartbeat()
        cancelAlarm()
        stopForeground(true)
        stopSelf()
        isServiceRunning = false
        Log.d(TAG, "Foreground service stopped")
    }

    private fun setTrackingEnabled(enabled: Boolean) {
        getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(trackingEnabledKey, enabled)
            .apply()
    }

    private fun isTrackingEnabled(): Boolean {
        return getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getBoolean(trackingEnabledKey, false)
    }

    private fun createNotification(contentText: String): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Location Tracking")
            .setContentText(contentText)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun startLocationUpdates() {
        if (locationManager == null) {
            Log.e(TAG, "LocationManager is null")
            return
        }

        try {
            locationListener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    handleLocationUpdate(location)
                }

                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {}
            }

            val hasFineLocation = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            val hasCoarseLocation = checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED

            if (hasFineLocation || hasCoarseLocation) {
                if (hasFineLocation) {
                    locationManager?.requestLocationUpdates(
                        LocationManager.GPS_PROVIDER,
                        timeFilter,
                        distanceFilter,
                        locationListener!!
                    )
                    locationManager?.requestLocationUpdates(
                        LocationManager.NETWORK_PROVIDER,
                        timeFilter,
                        distanceFilter,
                        locationListener!!
                    )
                } else if (hasCoarseLocation) {
                    locationManager?.requestLocationUpdates(
                        LocationManager.NETWORK_PROVIDER,
                        timeFilter,
                        distanceFilter,
                        locationListener!!
                    )
                }
                Log.d(TAG, "Location updates started")
            } else {
                Log.e(TAG, "Location permissions not granted")
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Exception starting location updates: ${e.message}")
        }
    }

    private fun stopLocationUpdates() {
        locationListener?.let {
            locationManager?.removeUpdates(it)
            locationListener = null
            Log.d(TAG, "Location updates stopped")
        }
    }

    private fun handleLocationUpdate(location: Location) {
        lastLocation = location
        Log.d(TAG, "Location updated: ${location.latitude}, ${location.longitude}")
        
        // Store location locally for batch upload
        storeLocationLocally(location)
        
        // Update notification
        val notification = createNotification("Lat: ${String.format("%.6f", location.latitude)}, Lng: ${String.format("%.6f", location.longitude)}")
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun storeLocationLocally(location: Location) {
        val prefs = getSharedPreferences("LocationPrefs", Context.MODE_PRIVATE)
        val locationsJson = prefs.getString("stored_locations", "[]")
        val locationsList = try {
            org.json.JSONArray(locationsJson)
        } catch (e: Exception) {
            org.json.JSONArray()
        }
        
        val locationObj = JSONObject().apply {
            put("latitude", location.latitude)
            put("longitude", location.longitude)
            put("timestamp", System.currentTimeMillis())
            put("accuracy", location.accuracy)
        }
        
        locationsList.put(locationObj)
        
        // Keep only last 100 locations
        if (locationsList.length() > 100) {
            val newArray = org.json.JSONArray()
            for (i in locationsList.length() - 100 until locationsList.length()) {
                newArray.put(locationsList.get(i))
            }
            prefs.edit().putString("stored_locations", newArray.toString()).apply()
        } else {
            prefs.edit().putString("stored_locations", locationsList.toString()).apply()
        }
    }

    private fun buildServerLocations(rawLocations: org.json.JSONArray, partnerId: String): org.json.JSONArray {
        val serverLocations = org.json.JSONArray()
        val partnerIdNumber = partnerId.toIntOrNull()
        for (i in 0 until rawLocations.length()) {
            val item = rawLocations.optJSONObject(i) ?: continue
            val locationObj = JSONObject().apply {
                put("latitude", item.optDouble("latitude"))
                put("longitude", item.optDouble("longitude"))
                if (partnerIdNumber != null) {
                    put("partner_id", partnerIdNumber)
                } else {
                    put("partner_id", partnerId)
                }
                put("action", "get_live_location")
            }
            serverLocations.put(locationObj)
        }
        return serverLocations
    }

    fun sendLocationsToServer() {
        if (userId.isNullOrEmpty() || apiUrl.isNullOrEmpty()) {
            Log.e(TAG, "User ID or API URL is missing")
            return
        }

        val prefs = getSharedPreferences("LocationPrefs", Context.MODE_PRIVATE)
        val locationsJson = prefs.getString("stored_locations", "[]")
        
        try {
            val locationsList = org.json.JSONArray(locationsJson)
            if (locationsList.length() == 0) {
                Log.d(TAG, "No locations to send")
                return
            }
            val serverLocations = buildServerLocations(locationsList, userId!!)
            if (serverLocations.length() == 0) {
                Log.d(TAG, "No valid locations to send after payload transform")
                return
            }

            // Send locations in batch
            Thread {
                try {
                    val payload = JSONObject().apply {
                        put("locations", serverLocations)
                    }
                    Log.d(TAG, "📤 Location update payload: ${payload}")
                    Log.d(TAG, "Location API URL before call: $apiUrl")

                    val url = URL(apiUrl)
                    val conn = url.openConnection() as HttpURLConnection
                    conn.requestMethod = "POST"
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.doOutput = true
                    conn.connectTimeout = 30000
                    conn.readTimeout = 30000

                    val outputWriter = BufferedWriter(OutputStreamWriter(conn.outputStream))
                    outputWriter.write(payload.toString())
                    outputWriter.flush()
                    outputWriter.close()

                    val responseCode = conn.responseCode
                    val responseBody = try {
                        if (responseCode in 200..299) {
                            conn.inputStream.bufferedReader().use { it.readText() }
                        } else {
                            conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                        }
                    } catch (e: Exception) {
                        "Unable to read response body: ${e.message}"
                    }
                    if (responseCode == 200 || responseCode == 201) {
                        Log.d(
                            TAG,
                            "✅ Location update API success | code=$responseCode | count=${serverLocations.length()} | response=$responseBody"
                        )
                        // Clear stored locations after successful send
                        prefs.edit().putString("stored_locations", "[]").apply()
                    } else {
                        Log.e(
                            TAG,
                            "❌ Location update API failed | code=$responseCode | count=${serverLocations.length()} | response=$responseBody"
                        )
                    }
                    conn.disconnect()
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Exception sending locations: ${e.message}")
                }
            }.start()
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing stored locations: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "MyForegroundService"
        const val ACTION_START_SERVICE = "com.pravyatech.teknovativesolution.START_SERVICE"
        const val ACTION_STOP_SERVICE = "com.pravyatech.teknovativesolution.STOP_SERVICE"
        private const val ALARM_REQUEST_CODE = 1001
        private const val UPLOAD_INTERVAL_MS = 60 * 1000L // 1 minute

        private var instance: MyForegroundService? = null

        fun isServiceRunning(context: Context): Boolean {
            return instance?.isServiceRunning ?: false
        }

        fun sendLocationsToServerStatic(context: Context) {
            val service = instance
            if (service != null) {
                service.sendLocationsToServer()
            } else {
                Log.w(TAG, "Service instance is null in alarm flow, using fallback uploader")
                sendLocationsToServerFallback(context)
            }
        }

        private fun sendLocationsToServerFallback(context: Context) {
            val prefs = context.getSharedPreferences("UserDataPrefs", Context.MODE_PRIVATE)
            val userId = prefs.getString("user_id", null)
            val apiUrl = prefs.getString("url", null)
            if (userId.isNullOrEmpty() || apiUrl.isNullOrEmpty()) {
                Log.e(TAG, "Fallback upload aborted: user_id/url missing")
                return
            }

            val locationPrefs = context.getSharedPreferences("LocationPrefs", Context.MODE_PRIVATE)
            val locationsJson = locationPrefs.getString("stored_locations", "[]")
            val locationsList = try {
                org.json.JSONArray(locationsJson)
            } catch (e: Exception) {
                Log.e(TAG, "Fallback upload parse error: ${e.message}")
                org.json.JSONArray()
            }

            if (locationsList.length() == 0) {
                Log.d(TAG, "Fallback uploader: no locations to send")
                return
            }
            val partnerIdNumber = userId.toIntOrNull()
            val serverLocations = org.json.JSONArray()
            for (i in 0 until locationsList.length()) {
                val item = locationsList.optJSONObject(i) ?: continue
                val locationObj = JSONObject().apply {
                    put("latitude", item.optDouble("latitude"))
                    put("longitude", item.optDouble("longitude"))
                    if (partnerIdNumber != null) {
                        put("partner_id", partnerIdNumber)
                    } else {
                        put("partner_id", userId)
                    }
                    put("action", "get_live_location")
                }
                serverLocations.put(locationObj)
            }
            if (serverLocations.length() == 0) {
                Log.d(TAG, "Fallback uploader: no valid transformed locations")
                return
            }

            Thread {
                var conn: HttpURLConnection? = null
                try {
                    val payload = JSONObject().apply {
                        put("locations", serverLocations)
                    }
                    Log.d(TAG, "📤 Fallback location update payload: ${payload}")
                    Log.d(TAG, "Location API URL before call (fallback): $apiUrl")

                    conn = (URL(apiUrl).openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"
                        setRequestProperty("Content-Type", "application/json")
                        doOutput = true
                        connectTimeout = 30000
                        readTimeout = 30000
                    }

                    BufferedWriter(OutputStreamWriter(conn.outputStream)).use { writer ->
                        writer.write(payload.toString())
                        writer.flush()
                    }

                    val responseCode = conn.responseCode
                    val responseBody = try {
                        if (responseCode in 200..299) {
                            conn.inputStream.bufferedReader().use { it.readText() }
                        } else {
                            conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                        }
                    } catch (e: Exception) {
                        "Unable to read response body: ${e.message}"
                    }

                    if (responseCode == 200 || responseCode == 201) {
                        Log.d(
                            TAG,
                            "✅ Fallback location update success | code=$responseCode | count=${serverLocations.length()} | response=$responseBody"
                        )
                        locationPrefs.edit().putString("stored_locations", "[]").apply()
                    } else {
                        Log.e(
                            TAG,
                            "❌ Fallback location update failed | code=$responseCode | count=${serverLocations.length()} | response=$responseBody"
                        )
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Fallback uploader exception: ${e.message}")
                } finally {
                    conn?.disconnect()
                }
            }.start()
        }

        fun scheduleUploadWithAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, UploadAlarmReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                ALARM_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val triggerTime = System.currentTimeMillis() + UPLOAD_INTERVAL_MS
            
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // Android 12+ requires SCHEDULE_EXACT_ALARM permission
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerTime,
                            pendingIntent
                        )
                    } else {
                        // Fallback to inexact alarm if exact alarm permission is not granted
                        Log.w(TAG, "Exact alarm permission not granted, using inexact alarm")
                        alarmManager.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerTime,
                            pendingIntent
                        )
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerTime,
                        pendingIntent
                    )
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
                }
                Log.d(TAG, "Upload scheduled for ${Date(triggerTime)}")
            } catch (e: SecurityException) {
                Log.e(TAG, "Failed to schedule alarm: ${e.message}")
                // Fallback to inexact alarm
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerTime,
                            pendingIntent
                        )
                    } else {
                        alarmManager.set(AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
                    }
                    Log.d(TAG, "Fallback: Upload scheduled with inexact alarm for ${Date(triggerTime)}")
                } catch (e2: Exception) {
                    Log.e(TAG, "Failed to schedule fallback alarm: ${e2.message}")
                }
            }
        }

        fun scheduleServiceRestart(context: Context, delayMs: Long = 10_000L) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val restartIntent = Intent(context, MyForegroundService::class.java).apply {
                action = ACTION_START_SERVICE
            }
            val restartPendingIntent = PendingIntent.getService(
                context,
                2002,
                restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val triggerAt = System.currentTimeMillis() + delayMs
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        restartPendingIntent
                    )
                } else {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        restartPendingIntent
                    )
                }
                Log.d(TAG, "Scheduled service restart at ${Date(triggerAt)}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to schedule service restart: ${e.message}")
            }
        }
    }

    private fun loadPreferences() {
        val prefs = getSharedPreferences("UserDataPrefs", Context.MODE_PRIVATE)
        userId = prefs.getString("user_id", null)
        apiUrl = prefs.getString("url", null)
        timeFilter = prefs.getLong("time_filter", 60000)
        distanceFilter = prefs.getFloat("distance_filter", 10f)
        Log.d(TAG, "Loaded preferences - UserId: $userId, URL: $apiUrl, TimeFilter: $timeFilter, DistanceFilter: $distanceFilter")
    }

    fun updateUserData(userId: String?, url: String?, timeFilter: Long?, distanceFilter: Float?) {
        val prefs = getSharedPreferences("UserDataPrefs", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        
        userId?.let { editor.putString("user_id", it) }
        url?.let { editor.putString("url", it) }
        timeFilter?.let { editor.putLong("time_filter", it) }
        distanceFilter?.let { editor.putFloat("distance_filter", it) }
        
        editor.apply()
        
        this.userId = userId ?: this.userId
        this.apiUrl = url ?: this.apiUrl
        this.timeFilter = timeFilter ?: this.timeFilter
        this.distanceFilter = distanceFilter ?: this.distanceFilter
        
        Log.d(TAG, "User data updated - UserId: ${this.userId}, URL: ${this.apiUrl}")
        
        // Restart location updates with new filters
        if (isServiceRunning) {
            stopLocationUpdates()
            startLocationUpdates()
        }
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MyForegroundService::WakeLock")
        wakeLock?.acquire(10 * 60 * 60 * 1000L /*10 hours*/)
        Log.d(TAG, "WakeLock acquired")
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "WakeLock released")
            }
        }
        wakeLock = null
    }

    private fun cancelAlarm() {
        alarmManager?.let {
            val intent = Intent(this, UploadAlarmReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                ALARM_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            it.cancel(pendingIntent)
            Log.d(TAG, "Alarm cancelled")
        }
    }

    private fun startUploadHeartbeat() {
        uploadHandler.removeCallbacks(uploadRunnable)
        uploadHandler.postDelayed(uploadRunnable, UPLOAD_INTERVAL_MS)
        Log.d(TAG, "Upload heartbeat started")
    }

    private fun stopUploadHeartbeat() {
        uploadHandler.removeCallbacks(uploadRunnable)
        Log.d(TAG, "Upload heartbeat stopped")
    }

    init {
        instance = this
    }
}
