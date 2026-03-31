import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class DozeModeService {
  static const MethodChannel _channel =
      MethodChannel('com.pravyatech.dozeMode');
  static Timer? _monitoringTimer;
  static bool _isListening = false;

  /// Start listening for doze mode changes and monitor service status
  static void startListening() {
    if (_isListening) {
      debugPrint('DozeModeService: Already listening');
      return;
    }

    _isListening = true;
    debugPrint('DozeModeService: Starting doze mode monitoring');

    // Monitor service status periodically
    _startServiceMonitoring();

    // Monitor app lifecycle changes
    _monitorAppLifecycle();
  }

  /// Stop listening for doze mode changes
  static void stopListening() {
    if (!_isListening) {
      return;
    }

    _isListening = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    debugPrint('DozeModeService: Stopped monitoring');
  }

  /// Start periodic monitoring of service status
  static void _startServiceMonitoring() {
    // Check service status every 30 seconds
    _monitoringTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) async {
      await _checkAndRestartService();
    });

    // Initial check
    _checkAndRestartService();
  }

  /// Monitor app lifecycle to handle doze mode scenarios
  static void _monitorAppLifecycle() {
    // Note: This requires access to WidgetsBinding.instance
    // We'll handle this through a callback or by checking periodically
    // For now, the periodic timer will handle most cases
  }

  /// Check if service is running and restart if needed
  static Future<void> _checkAndRestartService() async {
    try {
      // Check if location permission is granted
      final locationPermission = await Permission.location.status;
      if (!locationPermission.isGranted) {
        debugPrint('DozeModeService: Location permission not granted');
        return;
      }

      // Check if GPS is enabled
      final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isGpsEnabled) {
        debugPrint('DozeModeService: GPS is disabled');
        return;
      }

      // Check if service is running
      final isRunning =
          await _channel.invokeMethod<bool>('isServiceRunning') ?? false;

      if (!isRunning) {
        debugPrint(
            'DozeModeService: Service not running, attempting to restart...');

        // Restart the service
        try {
          await _channel.invokeMethod('startService');
          debugPrint('DozeModeService: Service restarted successfully');
        } catch (e) {
          debugPrint('DozeModeService: Failed to restart service: $e');
        }
      } else {
        debugPrint('DozeModeService: Service is running correctly');
      }
    } catch (e) {
      debugPrint('DozeModeService: Error checking service status: $e');
    }
  }

  /// Handle app lifecycle state changes
  static void handleLifecycleChange(AppLifecycleState state) {
    debugPrint('DozeModeService: App lifecycle changed to: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        // App is back in foreground, check service status
        _checkAndRestartService();
        break;
      case AppLifecycleState.paused:
        // App is going to background, ensure service is running
        _ensureServiceRunning();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is inactive or detached
        break;
    }
  }

  /// Ensure service is running (called when app goes to background)
  static Future<void> _ensureServiceRunning() async {
    try {
      final isRunning =
          await _channel.invokeMethod<bool>('isServiceRunning') ?? false;

      if (!isRunning) {
        debugPrint(
            'DozeModeService: Ensuring service is running before going to background...');
        await _channel.invokeMethod('startService');
      }
    } catch (e) {
      debugPrint('DozeModeService: Error ensuring service is running: $e');
    }
  }

  /// Request to ignore battery optimizations (helps prevent doze mode from killing service)
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isDenied) {
        final result = await Permission.ignoreBatteryOptimizations.request();
        return result.isGranted;
      }
      return status.isGranted;
    } catch (e) {
      debugPrint('DozeModeService: Error requesting battery optimization: $e');
      return false;
    }
  }

  /// Check if battery optimizations are ignored
  static Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (e) {
      debugPrint('DozeModeService: Error checking battery optimization: $e');
      return false;
    }
  }
}
