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
import 'package:background_locator_2/background_locator.dart';
import 'package:background_locator_2/location_dto.dart';
import 'package:background_locator_2/settings/android_settings.dart'
    as androidSetting;
import 'package:background_locator_2/settings/ios_settings.dart';
import 'package:background_locator_2/settings/locator_settings.dart'
    as LocationAccuracy;

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
  LocationDto? lastLocation;

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
    try {
      // Set up isolate communication
      if (IsolateNameServer.lookupPortByName(
              LocationServiceRepository.isolateName) !=
          null) {
        IsolateNameServer.removePortNameMapping(
            LocationServiceRepository.isolateName);
      }
      IsolateNameServer.registerPortWithName(
          port.sendPort, LocationServiceRepository.isolateName);
      port.listen(
        (dynamic data) async {
          await updateUI(data);
        },
      );
      // Initialize BackgroundLocator after a delay to ensure app is fully loaded
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          initPlatformState();
        }
      });
    } catch (e) {
      debugPrint('Error setting up location services: $e');
      // Don't crash if this fails
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
    // Temporarily disable BackgroundLocator to prevent crashes
    // TODO: Re-enable after fixing BackgroundLocator initialization issues
    debugPrint('BackgroundLocator initialization skipped to prevent crashes');
    return;

    /* Commented out to prevent crashes - uncomment when BackgroundLocator is properly configured
    try {
      debugPrint('Initializing BackgroundLocator...');
      // Wrap in try-catch with stack trace to see what's failing
      await BackgroundLocator.initialize().catchError((error, stackTrace) {
        debugPrint('BackgroundLocator.initialize() failed: $error');
        debugPrint('StackTrace: $stackTrace');
        // Don't rethrow - let the app continue
        return null;
      });
      
      // Only continue if initialization succeeded
      if (await BackgroundLocator.isServiceRunning().catchError((e) {
        debugPrint('Error checking if service is running: $e');
        return false;
      })) {
        debugPrint('BackgroundLocator initialization done');
        final _isRunning = await BackgroundLocator.isServiceRunning();
        if (mounted) {
          setState(() {
            isRunning = _isRunning;
          });
        }
        onStart();
        debugPrint('Running ${isRunning.toString()}');
      }
    } catch (e, stackTrace) {
      debugPrint('Error in initPlatformState: $e');
      debugPrint('StackTrace: $stackTrace');
      // Don't crash the app if BackgroundLocator fails
      // The app should still work without background location
    }
    */
  }

  void onStart() async {
    if (await handleLocationPermission(context)) {
      await _startLocator();
      final _isRunning = await BackgroundLocator.isServiceRunning();
      setState(() {
        isRunning = _isRunning;
        lastLocation = null;
      });
    } else {
      // show error
    }
  }

  Future<bool> handleLocationPermission([BuildContext? context]) async {
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

  Future<void> updateUI(dynamic data) async {
    LocationDto? locationDto =
        (data != null) ? LocationDto.fromJson(data) : null;
    if (locationDto != null) {
      await _updateNotificationText(locationDto);
    }
  }

  Future<void> _updateNotificationText(LocationDto data) async {
    if (data == null) {
      print("data ===============> null");
      return;
    }
    await BackgroundLocator.updateNotificationText(
        title: "new location received",
        msg: "${DateTime.now()}",
        bigMsg: "${data.latitude}, ${data.longitude}");
  }

  // Main Code for location
  Future<void> _startLocator() async {
    Map<String, dynamic> data = {'countInit': 1};
    return await BackgroundLocator.registerLocationUpdate(
      LocationCallbackHandler.callback,
      initCallback: LocationCallbackHandler.initCallback,
      initDataCallback: data,
      disposeCallback: LocationCallbackHandler.disposeCallback,
      iosSettings: const IOSSettings(
          accuracy: LocationAccuracy.LocationAccuracy.NAVIGATION,
          distanceFilter: 0,
          showsBackgroundLocationIndicator: true,
          stopWithTerminate: false),
      autoStop: false,
      androidSettings: const androidSetting.AndroidSettings(
        accuracy: LocationAccuracy.LocationAccuracy.NAVIGATION,
        interval: 10,
        wakeLockTime: 1000000000,
        distanceFilter: 0,
        client: androidSetting.LocationClient.google,
        androidNotificationSettings: androidSetting.AndroidNotificationSettings(
            notificationChannelName: 'Location tracking',
            notificationIcon: "@mipmap/launcher_icon",
            notificationTitle: 'Start Location Tracking',
            notificationMsg: 'Track location in background',
            notificationBigMsg:
                'Background location is on to keep the app up-to-date with your location. This is required for main features to work properly when the app is not running.',
            notificationIconColor: Colors.grey,
            notificationTapCallback:
                LocationCallbackHandler.notificationCallback),
      ),
    );
  }

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
  // Step 2: Check if location services are enabled
  bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
  if (isLocationServiceEnabled) {
    if (GetStorage().hasData(isLoginSession) == true) {
      final Dio dio = Dio();
      String url = '${GetStorage().read(hostUrlLoginSession)}/geo/update';
      var headers = {
        'Cookie': 'session_id=c5a7fe5af5aa4b5940c4365a1592702650a6fed8'
      };
      final Map<String, dynamic> data = {
        "latitude": latitude,
        "longitude": longitude,
        "partner_id": GetStorage().read(userIdSession),
        "action": "get_live_location",
      };
      print("Localtion==================> $data");
      debugPrint("API URL before call (geo/update): $url");
      try {
        final response = await dio.request(
          url,
          options: Options(
            method: 'POST',
            headers: headers,
          ),
          data: jsonEncode(data),
        );
        if (response.statusCode == 200) {
          debugPrint(
              "Response Data ===============: ${json.encode(response.data)}");
        } else {
          debugPrint("Error: ${response.statusMessage}");
        }
      } catch (e) {
        debugPrint("Exception: $e");
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

@pragma('vm:entry-point')
class LocationCallbackHandler {
  @pragma('vm:entry-point')
  static Future<void> initCallback(Map<dynamic, dynamic> params) async {
    LocationServiceRepository myLocationCallbackRepository =
        LocationServiceRepository();
    await myLocationCallbackRepository.init(params);
  }

  @pragma('vm:entry-point')
  static Future<void> disposeCallback() async {
    LocationServiceRepository myLocationCallbackRepository =
        LocationServiceRepository();
    await myLocationCallbackRepository.dispose();
  }

  @pragma('vm:entry-point')
  static Future<void> callback(LocationDto locationDto) async {
    LocationServiceRepository myLocationCallbackRepository =
        LocationServiceRepository();
    await myLocationCallbackRepository.callback(locationDto);
  }

  @pragma('vm:entry-point')
  static Future<void> notificationCallback() async {
    print('*notificationCallback');
  }
}

class LocationServiceRepository {
  static LocationServiceRepository instance = LocationServiceRepository._();
  LocationServiceRepository._();
  factory LocationServiceRepository() {
    return instance;
  }
  static const String isolateName = 'LocatorIsolate';
  int _count = -1;
  Future<void> init(Map<dynamic, dynamic> params) async {
    print("*Init callback handler");
    if (params.containsKey('countInit')) {
      dynamic tmpCount = params['countInit'];
      if (tmpCount is double) {
        _count = tmpCount.toInt();
      } else if (tmpCount is String) {
        _count = int.parse(tmpCount);
      } else if (tmpCount is int) {
        _count = tmpCount;
      } else {
        _count = -2;
      }
    } else {
      _count = 0;
    }
    print("$_count");
    final SendPort? send = IsolateNameServer.lookupPortByName(isolateName);
    send?.send(null);
  }

  Future<void> dispose() async {
    print("*Dispose callback handler");
    print("$_count");
    final SendPort? send = IsolateNameServer.lookupPortByName(isolateName);
    send?.send(null);
  }

  Future<void> callback(LocationDto locationDto) async {
    print(
        '======> $_count location in dart ===========> ${locationDto.toString()}');
    // await sendLatLongOfflineOnline(locationDto.latitude, locationDto.longitude);
    final SendPort? send = IsolateNameServer.lookupPortByName(isolateName);
    send?.send(locationDto.toJson());
    _count++;
  }
}
