package com.pravyatech.teknovativesolution

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.pravyatech.dozeMode"
    private val TAG = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    try {
                        startLocationService()
                        result.success(true)
                        Log.d(TAG, "Service started successfully")
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to start service: ${e.message}", null)
                        Log.e(TAG, "Error starting service: ${e.message}")
                    }
                }
                "stopService" -> {
                    try {
                        stopLocationService()
                        result.success(true)
                        Log.d(TAG, "Service stopped successfully")
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to stop service: ${e.message}", null)
                        Log.e(TAG, "Error stopping service: ${e.message}")
                    }
                }
                "isServiceRunning" -> {
                    try {
                        val isRunning = MyForegroundService.isServiceRunning(this@MainActivity)
                        result.success(isRunning)
                        Log.d(TAG, "Service running status: $isRunning")
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to check service status: ${e.message}", null)
                        Log.e(TAG, "Error checking service status: ${e.message}")
                    }
                }
                "sendUserIdData" -> {
                    try {
                        val rawUserId = call.argument<Any>("user_id")
                        val userId = rawUserId?.toString()
                        val rawUrl = call.argument<Any>("url")
                        val url = rawUrl?.toString()
                        val timeFilter = call.argument<Long>("time_filter") ?: 60000L
                        val distanceFilter = call.argument<Double>("distance_filter")?.toFloat() ?: 10f

                        if (userId.isNullOrBlank() || url.isNullOrBlank()) {
                            Log.e(TAG, "Invalid user data from Flutter: userId=$userId, url=$url")
                        }
                        
                        saveUserData(userId, url, timeFilter, distanceFilter)
                        
                        // Update service if it's running by binding to it
                        if (MyForegroundService.isServiceRunning(this@MainActivity)) {
                            try {
                                val serviceIntent = Intent(this@MainActivity, MyForegroundService::class.java)
                                val serviceConnection = object : ServiceConnection {
                                    override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                                        try {
                                            val binder = service as? MyForegroundService.LocalBinder
                                            binder?.getService()?.updateUserData(userId, url, timeFilter, distanceFilter)
                                            Log.d(TAG, "Service data updated via binding")
                                        } catch (e: Exception) {
                                            Log.e(TAG, "Error updating service data: ${e.message}")
                                        } finally {
                                            try {
                                                unbindService(this)
                                            } catch (e: Exception) {
                                                Log.e(TAG, "Error unbinding service: ${e.message}")
                                            }
                                        }
                                    }
                                    
                                    override fun onServiceDisconnected(name: ComponentName?) {
                                        Log.d(TAG, "Service disconnected")
                                    }
                                }
                                bindService(serviceIntent, serviceConnection, Context.BIND_AUTO_CREATE)
                            } catch (e: Exception) {
                                Log.e(TAG, "Error binding to service: ${e.message}")
                                // Service will pick up the new data from SharedPreferences on next update
                            }
                        }
                        
                        result.success(true)
                        Log.d(TAG, "User data saved: userId=$userId, url=$url")
                    } catch (e: Exception) {
                        result.error("DATA_ERROR", "Failed to save user data: ${e.message}", null)
                        Log.e(TAG, "Error saving user data: ${e.message}")
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startLocationService() {
        val serviceIntent = Intent(this@MainActivity, MyForegroundService::class.java).apply {
            action = MyForegroundService.ACTION_START_SERVICE
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        Log.d(TAG, "Location service start requested")
    }

    private fun stopLocationService() {
        val serviceIntent = Intent(this@MainActivity, MyForegroundService::class.java).apply {
            action = MyForegroundService.ACTION_STOP_SERVICE
        }
        stopService(serviceIntent)
        Log.d(TAG, "Location service stop requested")
    }

    private fun saveUserData(userId: String?, url: String?, timeFilter: Long, distanceFilter: Float) {
        val prefs = getSharedPreferences("UserDataPrefs", android.content.Context.MODE_PRIVATE)
        val editor = prefs.edit()
        
        userId?.let { editor.putString("user_id", it) }
        url?.let { editor.putString("url", it) }
        editor.putLong("time_filter", timeFilter)
        editor.putFloat("distance_filter", distanceFilter)
        
        editor.apply()
        Log.d(TAG, "User data saved to SharedPreferences")
    }
}

