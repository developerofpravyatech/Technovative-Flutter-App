// ignore_for_file: library_prefixes

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:teknovative_solution/notification_service.dart';
import 'package:teknovative_solution/resources/extension.dart';
import 'package:teknovative_solution/resources/session_string.dart';
import 'package:teknovative_solution/resources/theme.dart';
import 'package:teknovative_solution/route/app_module.dart';
import 'package:teknovative_solution/route/route.dart';

import 'dart:core';
import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:isolate';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dependency_injection.dart';
import 'firebase_options.dart';
import 'shared/background_location_disclosure.dart';
import 'shared/get_storage_repository.dart';

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

bool _isGpsFeatureEnabledGlobal() {
  final rawGps = GetStorage().read(isGpsFeatureSession);
  if (rawGps == null) return true;
  return rawGps == true ||
      rawGps == 1 ||
      rawGps.toString().toLowerCase() == 'true';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureFirebaseInitialized();

  // Initialize GetStorage after Firebase
  await Get.putAsync(() => GetStorage.init());

  // Set up background message handler after Firebase is initialized
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize other services
  DependencyInjection.init();
  // await FlutterDownloader.initialize();

  runApp(const MyApp());
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("Background message received: ${message.data}");
  await _ensureFirebaseInitialized();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final NotificationServices notificationServices = NotificationServices();

  ReceivePort port = ReceivePort();
  bool? isRunning;
  dynamic lastLocation;

  @override
  void initState() {
    super.initState();
    // Initialize Firebase services after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFirebaseServices();
      // Defer location initialization to avoid blocking the UI
      _initializeLocationServices();
    });
    _checkConnectivity();
    // Subscribe to the connectivity changes
    _subscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      setState(() {
        connectionStatus = _getConnectionStatus(results);
      });
    });
  }

  Future<void> _initializeLocationServices() async {
    if (!_isGpsFeatureEnabledGlobal()) {
      debugPrint('is_gps_feature is false. Skipping location isolate setup.');
      return;
    }
    try {
      const isolateName = 'LocatorIsolate';
      if (IsolateNameServer.lookupPortByName(isolateName) != null) {
        IsolateNameServer.removePortNameMapping(isolateName);
      }
      IsolateNameServer.registerPortWithName(port.sendPort, isolateName);
      port.listen(
        (dynamic data) async {
          await updateUI(data);
        },
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          initPlatformState();
        }
      });
    } catch (e) {
      debugPrint('Error setting up location services: $e');
    }
  }

  Future<void> _initializeFirebaseServices() async {
    // Ensure Firebase is initialized before using Firebase services
    try {
      await notificationServices.requestNotificationPermission();
      notificationServices.firebaseInit(context);
      // Setup token refresh listener
      notificationServices.isTokenRefresh();
      // Try to get initial token (this helps ensure token is available)
      await Future.delayed(const Duration(seconds: 2));
      String? initialToken = await notificationServices.setupTokenListener();
      debugPrint("Initial token from setup: $initialToken");
    } catch (e) {
      debugPrint("Error initializing Firebase services: $e");
    }
  }

  late StreamSubscription<List<ConnectivityResult>> _subscription;
  String connectionStatus = 'Checking connection...';

  Future<void> _checkConnectivity() async {
    final List<ConnectivityResult> result =
        await Connectivity().checkConnectivity();
    setState(() {
      connectionStatus = _getConnectionStatus(result);
    });
  }

  String _getConnectionStatus(List<ConnectivityResult> results) {
    // Check if any connection is available
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      return 'No Internet Connection';
    }

    // Check for active connections
    if (results.contains(ConnectivityResult.mobile) ||
        results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet) ||
        results.contains(ConnectivityResult.vpn) ||
        results.contains(ConnectivityResult.bluetooth) ||
        results.contains(ConnectivityResult.other)) {
      // Send any stored locations when internet is restored
      _sendStoredLocations();
      return 'Connected to the internet';
    }

    return 'Unknown Connection';
  }

  Future<void> initPlatformState() async {
    debugPrint('BackgroundLocator initialization skipped');
  }

  void onStart() async {
    if (await handleLocationPermission(context)) {
      setState(() {
        isRunning = false;
        lastLocation = null;
      });
    }
  }

  Future<bool> handleLocationPermission([BuildContext? context]) async {
    if (!_isGpsFeatureEnabledGlobal()) {
      debugPrint('is_gps_feature is false. handleLocationPermission skipped.');
      return false;
    }
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Notify the user to enable location services
      showErrorSnackbar("Location services are disabled. Please enable them.");
      return false;
    }
    PermissionStatus permission;
    if (Platform.isIOS) {
      var status = await Permission.locationWhenInUse.status;
      if (!status.isGranted) {
        var status = await Permission.locationWhenInUse.request();
        if (status.isGranted) {
          var status = await Permission.locationAlways.request();
          if (status.isGranted) {
            //
          } else {
            //
          }
        } else {
          //The user deny the permission
        }
        if (status.isPermanentlyDenied) {
          //When the user previously rejected the permission and select never ask again
          //Open the screen of settings
          // bool res = await openAppSettings();
        }
      } else {
        //In use is available, check the always in use
        var status = await Permission.locationAlways.status;
        if (!status.isGranted) {
          var status = await Permission.locationAlways.request();
          if (status.isGranted) {
            // write Something
          } else {
            // write Something
          }
        } else {
          // previously available, do some stuff or nothing
        }
      }
    } else if (Platform.isAndroid) {
      // Request foreground location first
      permission = await Permission.location.request();
      if (!permission.isGranted) {
        if (permission.isPermanentlyDenied) {
          showErrorSnackbar(
            "Location permissions are permanently denied, please enable them from settings.",
          );
          return false;
        }
        return false;
      }
      // Background location: show prominent disclosure before requesting (Google Play)
      final hasBackground = await Permission.locationAlways.isGranted;
      if (!hasBackground && context != null && context.mounted) {
        final consented = await BackgroundLocationDisclosure.show(context);
        if (consented) {
          await Permission.locationAlways.request();
        }
      }
      return true;
    }

    return false;
  }

  Future<void> updateUI(dynamic data) async {}

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    final storageRepository = Get.find<GetStorageRepository>();
    final isLoggedIn = storageRepository.hasData(isLoginSession) &&
        storageRepository.read(isLoginSession) == true;

    return GetMaterialApp(
      title: 'ERP APP',
      theme: Themes.getTheme(context),
      debugShowCheckedModeBanner: false,
      initialRoute: isLoggedIn ? AppRoute.home : AppRoute.login,
      getPages: AppPage.routes,
    );
  } 
}

Future<void> sendLatLong(double latitude, double longitude) async {
  if (!_isGpsFeatureEnabledGlobal()) {
    debugPrint('is_gps_feature is false. sendLatLong skipped.');
    return;
  }
  // Step 2: Check if location services are enabled
  bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
  if (isLocationServiceEnabled) {
    if (GetStorage().hasData(isLoginSession) == true) {
      final Dio dio = Dio();
      final hostUrl = GetStorage().read(hostUrlLoginSession) ?? 'https://app.teknovative.com';
      String url = '$hostUrl/geo/update';
      final userId = GetStorage().read(userIdSession);
      final sessionId = GetStorage().read(odooSessionId);
      
      var headers = <String, String>{};
      if (sessionId != null && sessionId.toString().isNotEmpty) {
        headers['Cookie'] = 'session_id=$sessionId';
      }

      final Map<String, dynamic> data = {
        "latitude": latitude,
        "longitude": longitude,
        "partner_id": userId,
        "action": "get_live_location",
      };
      debugPrint("Live GPS Tracking Payload (User ID: $userId) =====> $data");
      debugPrint("API URL before call (geo/update): $url");
      try {
        final response = await dio.request(
          url,
          options: Options(
            method: 'POST',
            headers: headers.isNotEmpty ? headers : null,
            validateStatus: (status) => true,
          ),
          data: jsonEncode(data),
        );
        if (response.statusCode == 200) {
          debugPrint(
              "GPS Tracking Response Data ===============: ${json.encode(response.data)}");
        } else {
          debugPrint("GPS Tracking Error: ${response.statusMessage}");
        }
      } catch (e) {
        debugPrint("GPS Tracking Exception: $e");
      }
    }
  } else {
    // print("Location services are disabled. Please enable them.");
    // await Geolocator.openLocationSettings();
  }
}

final GetStorage _storage = GetStorage();
const String storedLocationsKey = 'storedLocations';

// Send Lat Long Offline & Online
Future<void> sendLatLongOfflineOnline(double latitude, double longitude) async {
  if (!_isGpsFeatureEnabledGlobal()) return;
  // Step 1: Check for internet connection
  var connectivityResult = await (Connectivity().checkConnectivity());
  if (connectivityResult != ConnectivityResult.none) {
    // Internet is available
    sendLatLong(latitude, longitude);
    // Send any stored locations if available (when internet is on)
    await _sendStoredLocations();
  } else {
    // No internet, store location locally
    await _storeLocationLocally(latitude, longitude);
  }
}

List<dynamic> storedLocations = [];
// Store location locally in case of no internet
Future<void> _storeLocationLocally(double latitude, double longitude) async {
  storedLocations = _storage.read(storedLocationsKey) ?? [];
  // Add the new location in list and then this list store locally
  storedLocations.add({
    'latitude': latitude,
    'longitude': longitude,
    'partner_id': GetStorage().read(userIdSession),
    "action": "get_live_location",
  });
  // Save the updated list
  await _storage.write(storedLocationsKey, storedLocations);
  print("storedLocations Ḷist ==========> ${storedLocations}");
  print('Location stored locally ==========> $latitude, $longitude');
}

// Send stored locations when internet is available
Future<void> _sendStoredLocations() async {
  List<dynamic> storedLocations = _storage.read(storedLocationsKey) ?? [];
  if (storedLocations.isNotEmpty) {
    for (var location in storedLocations) {
      // api call
      sendLatLong(location['latitude'], location['longitude']);
    }
    // Clear stored locations after sending
    await _storage.remove(storedLocationsKey);
    storedLocations.clear();
  }
}


