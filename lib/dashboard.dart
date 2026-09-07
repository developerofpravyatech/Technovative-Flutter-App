import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:teknovative_solution/resources/color.dart';
import 'package:teknovative_solution/resources/constants.dart';
import 'package:teknovative_solution/resources/session_string.dart';
import 'package:teknovative_solution/resources/theme.dart';
import 'package:upgrader/upgrader.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

import 'package:teknovative_solution/route/route.dart';

import 'doze_mode_service.dart';
import 'main.dart';
import 'shared/background_location_disclosure.dart';
import 'shared/common/image_constant.dart';
import 'shared/odoo_web_auth.dart';

// ignore: must_be_immutable
InAppWebViewController? webViewController;

class DashboardScreen extends StatefulWidget {
  final String? webHostUrl;
  const DashboardScreen({super.key, this.webHostUrl});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  //late WebViewController webViewController;
  bool contentLLoading = false;
  bool isServiceStarted = false;
  bool showNativeDashboard = false;
  int selectedFilterIndex = 0;
  double? liveLat;
  double? liveLng;
  bool isLocating = false;
 
  StreamSubscription<Position>? _positionStreamSubscription;

  int odooLeadsCount = 0;
  int odooPartnersCount = 0;
  int odooSalesCount = 0;
  int odooTasksCount = 0;
  List<Map<String, dynamic>> odooRecentLeads = [];
  bool isLoadingOdooMetrics = false;

  Future<void> _fetchOdooDashboardMetrics() async {
    final box = GetStorage();
    final host = box.read(hostUrlLoginSession)?.toString() ?? box.read(whostUrl)?.toString();
    final sessionId = box.read(odooSessionId)?.toString();

    if (host == null || host.isEmpty || sessionId == null || sessionId.isEmpty) return;

    if (mounted) setState(() => isLoadingOdooMetrics = true);

    try {
      final metrics = await OdooWebAuth.fetchOdooMetrics(
        hostUrl: host,
        sessionId: sessionId,
      );
      if (mounted) {
        setState(() {
          odooLeadsCount = metrics['leadsCount'] ?? 0;
          odooPartnersCount = metrics['partnersCount'] ?? 0;
          odooSalesCount = metrics['salesCount'] ?? 0;
          odooTasksCount = metrics['tasksCount'] ?? 0;
          odooRecentLeads = List<Map<String, dynamic>>.from(metrics['recentLeads'] ?? []);
          isLoadingOdooMetrics = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading dynamic Odoo dashboard metrics: $e");
      if (mounted) setState(() => isLoadingOdooMetrics = false);
    }
  }

  bool get _isGpsFeatureEnabled {
    final box = GetStorage();
    final rawGps = box.read(isGpsFeatureSession);
    if (rawGps == null) return true;
    return rawGps == true ||
        rawGps == 1 ||
        rawGps.toString().toLowerCase() == 'true';
  }

  Future<void> _fetchCurrentLocation() async {
    if (!_isGpsFeatureEnabled) return;
    if (isLocating) return;
    setState(() => isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();
      if (serviceEnabled &&
          (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse)) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        if (mounted) {
          setState(() {
            liveLat = position.latitude;
            liveLng = position.longitude;
          });
          await sendLatLongOfflineOnline(position.latitude, position.longitude);
        }
      }
    } catch (e) {
      debugPrint("Location fetch error: $e");
    } finally {
      if (mounted) {
        setState(() => isLocating = false);
      }
    }
  }

  void _startLocationStream() async {
    if (!_isGpsFeatureEnabled) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();
      
      final box = GetStorage();
      bool hasPrompted = box.read('hasPromptedLocationPermission') == true;

      // Only prompt system location permission once across the entire application lifecycle
      if (permission == LocationPermission.denied && !hasPrompted) {
        await box.write('hasPromptedLocationPermission', true);
        permission = await Geolocator.requestPermission();
      }

      if (serviceEnabled &&
          (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse)) {
        const locationSettings = LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        );
        _positionStreamSubscription =
            Geolocator.getPositionStream(locationSettings: locationSettings)
                .listen(
          (Position position) {
            if (mounted) {
              setState(() {
                liveLat = position.latitude;
                liveLng = position.longitude;
              });
              sendLatLongOfflineOnline(position.latitude, position.longitude);
            }
          },
          onError: (error) {
            debugPrint("GPS position stream error: $error");
          },
        );
      }
    } catch (e) {
      debugPrint("Failed to start location stream: $e");
    }
  }


  bool _isReauthenticating = false;

  Future<void> _injectOdooSessionAndLoad(
      InAppWebViewController controller, {bool forceReauth = false}) async {
    if (_isReauthenticating) return;
    _isReauthenticating = true;
    try {
      final box = GetStorage();
      String? host = box.read(hostUrlLoginSession)?.toString() ?? box.read(whostUrl)?.toString();
      final login = box.read(userNameSession)?.toString();
      final password = box.read(userPass)?.toString();
      final db = box.read(odooDbSession)?.toString();
      String? sessionId = box.read(odooSessionId)?.toString();

      if (host == null || host.isEmpty) return;

      // Clean host URL to root base URL without /web or /web/login
      String baseHost = host.replaceAll(RegExp(r'/web(/login)?/?$'), '');
      if (baseHost.endsWith('/')) {
        baseHost = baseHost.substring(0, baseHost.length - 1);
      }

      // Re-authenticate Odoo web session if forced or if session ID is missing
      if (forceReauth || sessionId == null || sessionId.isEmpty) {
        if (login != null && password != null) {
          final newSessionId = await OdooWebAuth.authenticate(
            hostUrl: baseHost,
            db: db ?? '',
            login: login,
            password: password,
          );
          if (newSessionId != null && newSessionId.isNotEmpty) {
            sessionId = newSessionId;
            await box.write(odooSessionId, sessionId);
          }
        }
      }

      final target = (widget.webHostUrl != null && widget.webHostUrl!.isNotEmpty)
          ? widget.webHostUrl!
          : '$baseHost/web';

      if (sessionId != null && sessionId.isNotEmpty) {
        try {
          final uri = Uri.parse(baseHost);
          final domain = uri.host;

          for (final path in ['/', '/web', '/web/login']) {
            await CookieManager.instance().setCookie(
              url: WebUri('$baseHost$path'),
              name: 'session_id',
              value: sessionId,
              domain: domain.isNotEmpty ? domain : null,
              path: '/',
              isHttpOnly: false,
              isSecure: uri.scheme == 'https',
            );
          }
          debugPrint('Injected Odoo session_id cookie ($sessionId) for $baseHost');
        } catch (e) {
          debugPrint('Failed to inject Odoo session cookie: $e');
        }
      }

      final headers = <String, String>{};
      if (sessionId != null && sessionId.isNotEmpty) {
        headers['Cookie'] = 'session_id=$sessionId';
      }
      debugPrint('Loading WebView target: $target with session cookie headers');
      await controller.loadUrl(
        urlRequest: URLRequest(
          url: WebUri.uri(Uri.parse(target)),
          headers: headers.isNotEmpty ? headers : null,
        ),
      );
    } finally {
      _isReauthenticating = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final box = GetStorage();
    final userId = box.read(userIdSession);
    showNativeDashboard = userId == 2 || userId == '2';

    // Start background & location services if GPS feature is enabled
    if (_isGpsFeatureEnabled) {
      sendUserIdToNative(); 
      checkServiceAndGpsStatus();
      startBackgroundService();
      _fetchCurrentLocation();
      _startLocationStream();
    } else {
      debugPrint("is_gps_feature is false: Skipping GPS tracking and permission requests.");
    }
    _fetchOdooDashboardMetrics();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    DozeModeService.stopListening();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isGpsFeatureEnabled) {
      DozeModeService.handleLifecycleChange(state);
      if (state == AppLifecycleState.resumed) {
        checkServiceAndGpsStatus();
      }
    }
  }

  Future<void> sendUserIdToNative() async {
    // Only run on Android - method channel is Android-specific
    if (!Platform.isAndroid) {
      debugPrint("sendUserIdToNative: Skipped on non-Android platform");
      return;
    }

    try {
      const platform = MethodChannel('com.pravyatech.dozeMode');
      final rawUserId = GetStorage().read(userIdSession);
      final rawHost = GetStorage().read(hostUrlLoginSession);
      final userId = rawUserId?.toString();
      final host = rawHost?.toString();
      if (userId == null || userId.isEmpty || host == null || host.isEmpty) {
        debugPrint(
            "sendUserIdToNative: Missing user/session data. userId=$userId, host=$host");
        // Session data may still be syncing right after login; retry once.
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            sendUserIdToNative();
          }
        });
        return;
      }

      var data = {
        'user_id': userId,
        'url': '$host/geo/update',
        'time_filter': GetStorage().read("time_filter"),
        'distance_filter': GetStorage().read("distance_filter"),
      };

      debugPrint("Service Data: $data");
      await platform.invokeMethod('sendUserIdData', data);
    } on PlatformException catch (e) {
      debugPrint("Failed to send user ID: '${e.message}'.");
      debugPrint("Error code: ${e.code}, Details: ${e.details}");
    } on MissingPluginException catch (e) {
      debugPrint("Method channel not found: ${e.message}");
      debugPrint(
          "Make sure the app is fully rebuilt after package name change");
    } catch (e) {
      debugPrint("Unexpected error sending user ID: $e");
    }
  }

  Future<void> checkServiceAndGpsStatus() async {
    bool gpsEnabled = false;
    bool serviceRunning = false;
    try {
      // Check if GPS is enabled
      gpsEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('Error checking GPS status: $e');
    }

    // Only check service on Android
    if (Platform.isAndroid) {
      try {
        // Check if background service is running via MethodChannel
        const platform = MethodChannel('com.pravyatech.dozeMode');
        serviceRunning =
            await platform.invokeMethod('isServiceRunning') ?? false;
      } on MissingPluginException catch (e) {
        debugPrint('Method channel not found: ${e.message}');
        debugPrint('Rebuild the app after package name change');
      } catch (e) {
        debugPrint('Error checking service status: $e');
      }
    }

    setState(() {
      isServiceStarted = gpsEnabled && serviceRunning;
    });
  }

  startBackgroundService() async {
    if (!_isGpsFeatureEnabled) return;
    // Only on Android
    if (!Platform.isAndroid) {
      debugPrint("startBackgroundService: Skipped on non-Android platform");
      return;
    }

    await requestPermissions(context);
    // Start service only if we have location permission (user saw disclosure before request)
    if (await Permission.location.isGranted) {
      try {
        const platform = MethodChannel('com.pravyatech.dozeMode');
        await platform.invokeMethod('startService');
        DozeModeService.startListening();
      } on MissingPluginException catch (e) {
        debugPrint('Method channel not found: ${e.message}');
        debugPrint('Rebuild the app after package name change');
      } catch (e) {
        debugPrint('Error starting background service: $e');
      }
    }
  }

  /// Requests permissions. Shows prominent disclosure BEFORE any location permission (Google Play requirement).
  Future<void> requestPermissions(BuildContext context) async {
    if (Platform.isAndroid) {
      final hasLocation = await Permission.location.isGranted;
      final hasBackgroundLocation = await Permission.locationAlways.isGranted;
      // Show disclosure before asking for location if we need any location permission
      if ((!hasLocation || !hasBackgroundLocation) && context.mounted) {
        final userConsented = await BackgroundLocationDisclosure.show(context);
        if (!userConsented) {
          // User chose "Not Now" - skip location requests
          await Permission.ignoreBatteryOptimizations.request();
          if (await Permission.notification.isDenied) {
            await Permission.notification.request();
          }
          return;
        }
      }
      // User consented (or already had permission): request location
      await Permission.location.request();
      await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();
    } else {
      await Permission.location.request();
      await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();
    }

    await Permission.ignoreBatteryOptimizations.request();

    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  /// Ensures background location permission (with disclosure if needed) then starts the service.
  Future<void> _ensureBackgroundLocationAndStart() async {
    if (!Platform.isAndroid) return;
    // Show prominent disclosure if background location not yet granted
    if (!await Permission.locationAlways.isGranted && mounted) {
      final consented = await BackgroundLocationDisclosure.show(context);
      if (consented) {
        await Permission.locationAlways.request();
      }
    }
    final started = await startLocationService();
    if (mounted) {
      setState(() => isServiceStarted = started);
    }
    await checkServiceAndGpsStatus();
  }

  Future<bool> startLocationService() async {
    if (!Platform.isAndroid) {
      debugPrint("startLocationService: Skipped on non-Android platform");
      return false;
    }

    try {
      const platform = MethodChannel('com.pravyatech.dozeMode');
      await platform.invokeMethod('startService');
      DozeModeService.startListening();
      final running = await platform.invokeMethod<bool>('isServiceRunning');
      return running ?? false;
    } on MissingPluginException catch (e) {
      debugPrint('Method channel not found: ${e.message}');
      debugPrint('Rebuild the app after package name change');
      return false;
    } catch (e) {
      debugPrint('Error starting location service: $e');
      return false;
    }
  }

  Future<bool> stopLocationService() async {
    if (!Platform.isAndroid) {
      debugPrint("stopLocationService: Skipped on non-Android platform");
      return false;
    }

    try {
      const platform = MethodChannel('com.pravyatech.dozeMode');
      await platform.invokeMethod('stopService');
      DozeModeService.stopListening();
      final running = await platform.invokeMethod<bool>('isServiceRunning');
      return !(running ?? false);
    } on MissingPluginException catch (e) {
      debugPrint('Method channel not found: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Error stopping location service: $e');
      return false;
    }
  }

  Future<void> _handleServiceToggle() async {
    if (!_isGpsFeatureEnabled) {
      Get.snackbar(
        'GPS Feature Disabled',
        'GPS tracking feature is disabled for your account.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (isServiceStarted) {
      final stopped = await stopLocationService();
      if (mounted) {
        setState(() => isServiceStarted = !stopped ? isServiceStarted : false);
      }
      await checkServiceAndGpsStatus();
      return;
    }

    bool gpsEnabled = false;
    try {
      gpsEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('Error checking GPS status: $e');
    }
    if (gpsEnabled) {
      await _ensureBackgroundLocationAndStart();
    } else {
      Get.snackbar(
        'GPS Required',
        'Please enable GPS to start tracking.',
        snackPosition: SnackPosition.BOTTOM,
      );
      await checkServiceAndGpsStatus();
    }
  }

  // open pdf code
  Future<void> getPDF(BuildContext context, url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      debugPrint('Could not launch $url');
    }
  }

  Future<void> openGoogleMapsUsingAddress(String location) async {
    final Uri url = Uri.parse(location);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  // When User Click on back button (System also) then display confirmation dialiog

  Future<bool?> showConfirmationDialog() {
    return Get.dialog(
      Dialog(
        child: Container(
          height: 285,
          // width: 300,
          // color: whiteColor,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(ImageConstant.exlementionMarkImg,
                    height: 80, width: 80),
                SizedBox(height: 15),
                Text("Are you sure",
                    style: TextStyle(
                        color: Color(0xff024950),
                        fontSize: 20,
                        fontWeight: fwt500)),
                SizedBox(height: 15),
                Padding(
                  padding: const EdgeInsets.only(left: 15.0, right: 15),
                  child: Text("You want to exit from the App?",
                      style: TextStyle(
                          fontSize: 17,
                          color: blackColor,
                          fontWeight: FontWeight.w300)),
                ),
                SizedBox(height: 15),
                SizedBox(
                  height: 43,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      blueButton("CANCEL", () {
                        Navigator.pop(Get.context!, false);
                      }, bWidth: 120, bHeight: 44, fontSize: 13, color: const Color(0xff024950)),
                      whiteButton("OK", () {
                        Navigator.pop(Get.context!, true);
                      }, bWidth: 120, bHeight: 44, fontSize: 13),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // )
    );
  }

  Future<void> _performLogoutCleanup() async {
    try {
      await stopLocationService();
    } catch (e) {
      debugPrint("Error stopping location service on logout: $e");
    }
    DozeModeService.stopListening();
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (e) {
      debugPrint("Error clearing cookies on logout: $e");
    }

    final box = GetStorage();
    await box.remove(isLoginSession);
    await box.remove(userNameSession);
    await box.remove(userPass);
    await box.remove(userIdSession);
    await box.remove(hostUrlLoginSession);
    await box.remove(whostUrl);
    await box.remove(isNativeAnalyticsSession);
    await box.remove(odooSessionId);
    await box.remove(odooDbSession);
    await box.remove(isGpsFeatureSession);

    Get.offAllNamed(AppRoute.login);
  }

  Future<void> _handleLogout() async {
    final confirmed = await Get.dialog<bool>(
      Dialog(
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(ImageConstant.exlementionMarkImg, height: 50, width: 50),
                const SizedBox(height: 12),
                const Text(
                  "Confirm Logout",
                  style: TextStyle(color: Color(0xff024950), fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Are you sure you want to exit and log out?",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    blueButton("CANCEL", () => Navigator.pop(Get.context!, false), bWidth: 120, bHeight: 44, fontSize: 13, color: const Color(0xff024950)),
                    whiteButton("LOGOUT", () => Navigator.pop(Get.context!, true), bWidth: 120, bHeight: 44, fontSize: 13),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await _performLogoutCleanup();
    }
  }

  Widget _buildHeaderStat(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color accentColor,
    required List<Color> bgGradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: bgGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(color: accentColor.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              Icon(Icons.more_horiz, color: Colors.grey[400], size: 16),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = selectedFilterIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedFilterIndex = index;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xff024950) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xff024950) : Colors.grey[300]!,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: const Color(0xff024950).withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildBarChartItem(String month, double ratio, String amount, {bool isSelected = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          amount,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isSelected ? const Color(0xff024950) : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 20,
          height: 80 * ratio,
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xff0385FE), Color(0xff024950)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : LinearGradient(
                    colors: [const Color(0xff024950).withOpacity(0.4), const Color(0xff024950).withOpacity(0.2)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          month,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xff024950) : Colors.grey[700],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBarItem(String title, double progress, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "${(progress * 100).toInt()}%",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: color.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(String title, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xff024950), size: 22),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(String title, String desc, String time, IconData icon, Color iconColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showActionDialog(BuildContext context, String actionTitle, String description) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xff024950)),
            const SizedBox(width: 8),
            Text(actionTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description, style: const TextStyle(fontSize: 13, color: Colors.black87)),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: "Notes / Details",
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff024950),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Get.back();
              Get.snackbar("Success", "$actionTitle action submitted successfully.", snackPosition: SnackPosition.BOTTOM);
            },
            child: const Text("SUBMIT", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildNativeDashboardAnalytics(BuildContext context) {
    final box = GetStorage();
    final userName = box.read(userNameSession)?.toString() ?? 'User';
    final rawHost = box.read(hostUrlLoginSession)?.toString() ?? box.read(whostUrl)?.toString() ?? 'app.teknovative.com';
    final cleanHost = rawHost.replaceAll('https://', '').replaceAll('http://', '').replaceAll('/web', '');
    final dbName = box.read(odooDbSession)?.toString() ?? 'Odoo DB';
   
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Classy Executive Hero Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff024950), Color(0xff0F2027), Color(0xff0052D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xff024950).withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isServiceStarted ? Colors.green.withOpacity(0.25) : Colors.orange.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isServiceStarted ? Colors.greenAccent : Colors.orangeAccent,
                          width: 0.9,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isServiceStarted ? Colors.greenAccent : Colors.orangeAccent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isServiceStarted ? "GPS TRACKING ACTIVE" : "GPS SERVICE INACTIVE",
                            style: TextStyle(
                              color: isServiceStarted ? Colors.greenAccent : Colors.orangeAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        InkWell(
                          onTap: isLoadingOdooMetrics ? null : _fetchOdooDashboardMetrics,
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: isLoadingOdooMetrics
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () {
                            setState(() {
                              showNativeDashboard = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xff0385FE), Color(0xff0052D4)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xff0385FE).withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.language_rounded, color: Colors.white, size: 13),
                                SizedBox(width: 5),
                                Text(
                                  "ERP Web",
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.asset(
                          'assets/appLogo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: const Color(0xff024950),
                            alignment: Alignment.center,
                            child: Text(
                              userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Admin Portal: $userName",
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "$cleanHost ($dbName)",
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildHeaderStat("CRM Leads", "$odooLeadsCount", Icons.leaderboard_outlined),
                      Container(height: 22, width: 1, color: Colors.white24),
                      _buildHeaderStat("Partners", "$odooPartnersCount", Icons.people_alt_outlined),
                      Container(height: 22, width: 1, color: Colors.white24),
                      _buildHeaderStat("Sales Orders", "$odooSalesCount", Icons.shopping_bag_outlined),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. Dynamic Odoo ERP Metrics Cards Grid (2x2)
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: "Live CRM Leads",
                  value: "$odooLeadsCount Opportunities",
                  subtext: "Odoo CRM Model",
                  icon: Icons.trending_up_rounded,
                  accentColor: const Color(0xff024950),
                  bgGradient: [const Color(0xffE8F8F5), Colors.white],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: "Clients & Contacts",
                  value: "$odooPartnersCount Partners",
                  subtext: "Odoo Res.Partner",
                  icon: Icons.people_outline_rounded,
                  accentColor: const Color(0xff0385FE),
                  bgGradient: [const Color(0xffEBF5FF), Colors.white],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: "Sales Orders",
                  value: "$odooSalesCount Orders",
                  subtext: "Odoo Sale.Order",
                  icon: Icons.shopping_cart_outlined,
                  accentColor: Colors.orange,
                  bgGradient: [const Color(0xffFDF2E9), Colors.white],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: "Project Tasks",
                  value: "$odooTasksCount Tasks",
                  subtext: "Odoo Project.Task",
                  icon: Icons.assignment_outlined,
                  accentColor: const Color(0xff8E44AD),
                  bgGradient: [const Color(0xffF5EEF8), Colors.white],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 3. Quick Action Tools
          const Text(
            "Quick Actions & Tools",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xff0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildActionButton("ERP Web Admin", Icons.language_rounded, () {
                  setState(() {
                    showNativeDashboard = false;
                  });
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton("GPS Tracking", isServiceStarted ? Icons.location_off : Icons.location_on, () {
                  _handleServiceToggle();
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton("Logout", Icons.logout_rounded, () {
                  _handleLogout();
                }),
              ),
            ],
          ),

          if (odooRecentLeads.isNotEmpty) ...[
            const SizedBox(height: 18),

            // 4. Live ERP Activity Feed (Real Odoo Data)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Live Odoo ERP Leads",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff1F3844),
                        ),
                      ),
                      Icon(Icons.feed_outlined, size: 18, color: Colors.grey[600]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...odooRecentLeads.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final title = item['name']?.toString() ?? 'New Opportunity';
                    final partner = item['partner_name']?.toString() ?? item['contact_name']?.toString() ?? 'Odoo Client';
                    final createDate = item['create_date']?.toString() ?? 'Just now';
                    return Column(
                      children: [
                        if (index > 0) const Divider(height: 20),
                        _buildActivityItem(
                          title,
                          "Client: $partner",
                          createDate.length > 10 ? createDate.substring(0, 10) : createDate,
                          Icons.business_center_outlined,
                          const Color(0xff0385FE),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        statusBarColor: showNativeDashboard ? Colors.white : const Color(0xff024950),
        statusBarIconBrightness: showNativeDashboard ? Brightness.dark : Brightness.light,
        statusBarBrightness: showNativeDashboard ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: showNativeDashboard ? Colors.white : const Color(0xff024950),
        systemNavigationBarIconBrightness: showNativeDashboard ? Brightness.dark : Brightness.light));
    return Container(
      color: showNativeDashboard ? Colors.white : const Color(0xff024950),
      child: SafeArea(
        child: UpgradeAlert(
          upgrader: Upgrader(
              durationUntilAlertAgain: const Duration(days: 1)),
          child: WillPopScope(
            onWillPop: () async {
              if (!showNativeDashboard && webViewController != null && await webViewController!.canGoBack()) {
                WebHistory? history = await webViewController!.getCopyBackForwardList();
                if (history != null && history.currentIndex != null && history.currentIndex! > 0) {
                  int prevIndex = history.currentIndex! - 1;
                  String? prevUrl = history.list?[prevIndex].url?.toString();
                  if (prevUrl != null && prevUrl != 'about:blank' && !prevUrl.endsWith('/about:blank')) {
                    await webViewController!.goBack();
                    return false;
                  }
                }
              }
              final confirmExit = await showConfirmationDialog();
              if (confirmExit == true) {
                await SystemNavigator.pop();
                return true;
              }
              return false;
            }, 
            child: Scaffold(
                backgroundColor: showNativeDashboard ? Colors.white : const Color(0xff024950),
                body: showNativeDashboard
                    ? _buildNativeDashboardAnalytics(context)
                    : Stack(
                        children: [
                          Column(
                            children: [
                              Expanded( 
                                child: InAppWebView(
                                  onWebViewCreated: (controller) async {
                                    webViewController = controller;
                                    await _injectOdooSessionAndLoad(controller);
                                  },
                                  shouldOverrideUrlLoading:
                                      (controller, navigationAction) async {
                                    var uri = navigationAction.request.url!;
                                    debugPrint(
                                        "url = > ${navigationAction.request.url}");
                                    if (uri.path.contains('/web/session/logout')) {
                                      await _performLogoutCleanup();
                                      return NavigationActionPolicy.CANCEL;
                                    }
                                    if (uri.scheme == 'tel' || uri.scheme == 'whatsapp' || uri.scheme == 'mailto') {
                                      await launchUrl(uri);
                                      return NavigationActionPolicy.CANCEL;
                                    } else if (uri.host == 'maps.google.com' &&
                                        uri.queryParameters.containsKey('q')) {
                                      final location = uri.queryParameters['q'];
                                      if (location != null) {
                                        await openGoogleMapsUsingAddress(
                                            "https://www.google.com/maps/search/?api=1&query=$location");
                                        return NavigationActionPolicy.CANCEL;
                                      }
                                    } else if (uri.path.contains('/maps/dir/')) {
                                      final Uri googleMapsUrl = uri;
                                      if (await canLaunchUrl(googleMapsUrl)) {
                                        await launchUrl(googleMapsUrl,
                                            mode: LaunchMode.externalApplication);
                                      }
                                      return NavigationActionPolicy.CANCEL;
                                    }
                                    return NavigationActionPolicy.ALLOW;
                                  },
                                  onDownloadStartRequest:
                                      (controller, downloadStartRequest) {
                                    getPDF(context,
                                        "${downloadStartRequest.url.uriValue}");
                                  },
                                  onLoadStart: (controller, url) {
                                    debugPrint("WebView started loading: $url");
                                    setState(() => contentLLoading = true);
                                  },
                                  onLoadStop: (controller, url) async {
                                    debugPrint("WebView finished loading: $url");
                                    final box = GetStorage();
                                    final isLoggedIn = box.read(isLoginSession) == true;
                                    if (!isLoggedIn) {
                                      await _performLogoutCleanup();
                                      return;
                                    }
                                    if (url != null && url.toString().contains('/web/login')) {
                                      debugPrint("WebView arrived at /web/login. Automatically authenticating session...");
                                      await _injectOdooSessionAndLoad(controller, forceReauth: true);
                                    } else {
                                      if (mounted) setState(() => contentLLoading = false);
                                    }
                                  },
                                  onReceivedError: (controller, request, error) {
                                    debugPrint("WebView error: ${error.description}");
                                    if (mounted) setState(() => contentLLoading = false);
                                  },
                                  onReceivedHttpError: (controller, request, response) {
                                    debugPrint(
                                        "WebView HTTP error: ${response.statusCode}");
                                    if (mounted) setState(() => contentLLoading = false);
                                  },
                                  initialSettings: InAppWebViewSettings(
                                      allowsBackForwardNavigationGestures: true,
                                      enableViewportScale: true,
                                      javaScriptEnabled: true,
                                      domStorageEnabled: true,
                                      databaseEnabled: true,
                                      pageZoom: 1,
                                      supportZoom: false,
                                      initialScale: 1,
                                      useShouldOverrideUrlLoading: true,
                                      transparentBackground: true,
                                      verticalScrollBarEnabled: false,
                                      allowsLinkPreview: true,
                                      allowsInlineMediaPlayback: true,
                                      sharedCookiesEnabled: true,
                                      thirdPartyCookiesEnabled: true,
                                      preferredContentMode:
                                          UserPreferredContentMode.MOBILE),
                                  onGeolocationPermissionsShowPrompt:
                                      (controller, origin) async {
                                    return GeolocationPermissionShowPromptResponse(
                                      origin: origin,
                                      allow: true,
                                      retain: true,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          Visibility(
                              visible: contentLLoading,
                              child: const Center(child: CircularProgressIndicator()))
                        ],
                      ),
            ),
          ),
        ),
      ),
    );
  }
}
