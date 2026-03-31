import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'resources/session_string.dart';

class NotificationServices {
  //initialising firebase message plugin - lazy initialization
  FirebaseMessaging get messaging => FirebaseMessaging.instance;

  //initialising firebase message plugin
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // function to request notifications permissions
  Future<void> requestNotificationPermission() async {
    NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: true,
        criticalAlert: true,
        provisional: true,
        sound: true);

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      //user granted permission
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      //user granted provisional permission
    } else {
      // AppSettings.openNotificationSettings();
      //user denied permission
    }
  }

  // function to initialise flutter local notification plugin to show notifications for android when app is active
  void initLocalNotifications(
      BuildContext context, RemoteMessage message) async {
    var androidInitializationSettings =
        const AndroidInitializationSettings('@mipmap/ic_launcher');
    var iosInitializationSettings = const DarwinInitializationSettings();

    var initializationSetting = InitializationSettings(
        android: androidInitializationSettings, iOS: iosInitializationSettings);

    await _flutterLocalNotificationsPlugin.initialize(initializationSetting,
        onDidReceiveNotificationResponse: (payload) {
      // handle interaction when app is active for android
      handleMessage(message);
    });
  }

  void firebaseInit(BuildContext context) {
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint("message => ${message.data}");
      initLocalNotifications(context, message);
      enableIOSNotifications();
      showNotification(message);
    });
  }

  // function to show visible notification when app is active
  Future<void> showNotification(RemoteMessage message) async {
    AndroidNotificationChannel channel = AndroidNotificationChannel(
        Random.secure().nextInt(100000).toString(),
        'High Importance Notifications',
        importance: Importance.max);

    AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
            channel.id.toString(), channel.name.toString(),
            channelDescription: 'your channel description',
            importance: Importance.high,
            priority: Priority.high);

    const DarwinNotificationDetails darwinNotificationDetails =
        DarwinNotificationDetails(
            presentAlert: true, presentBadge: true, presentSound: true);

    NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails, iOS: darwinNotificationDetails);
    print("object show : ${message.data}");

    // Check if user_id exists and is not null/empty
    final userId = message.data["user_id"];
    final action = message.data["action"];

    if (userId != null && userId.toString().isNotEmpty) {
      try {
        await _checkAndRequestLocationPermission(
            int.parse(userId.toString()), action?.toString() ?? "");
      } catch (e) {
        debugPrint("Error parsing user_id or action: $e");
        // Fall through to show regular notification
      }
    } else {
      // Show notification if user_id is null/empty and notification data exists
      if (message.notification != null) {
        Future.delayed(Duration.zero, () {
          _flutterLocalNotificationsPlugin.show(
              0,
              message.notification!.title ?? "Notification",
              message.notification!.body ?? "",
              notificationDetails);
        });
      }
    }
  }

  //function to get device token on which we will send the notifications
  Future<String> getDeviceToken() async {
    try {
      // Request notification permissions first
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint(
          "Notification permission status: ${settings.authorizationStatus}");

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // On iOS, wait for APNs token and then get FCM token
        if (Platform.isIOS) {
          // Wait for APNs token to be available (with retry logic)
          int retries = 5;
          int delayMs = 1000;

          for (int i = 0; i < retries; i++) {
            try {
              debugPrint("Attempt ${i + 1} to get FCM token...");

              // Check if APNs token is available
              String? apnsToken = await messaging.getAPNSToken();
              debugPrint(
                  "APNs token check (attempt ${i + 1}): ${apnsToken != null ? 'Available' : 'Not available'}");

              // Try to get FCM token
              String? token = await messaging.getToken();

              if (token != null && token.isNotEmpty) {
                debugPrint("FCM token successfully retrieved: $token");
                return token;
              } else {
                debugPrint("FCM token is null or empty (attempt ${i + 1})");
              }

              // If this is not the last retry, wait before trying again
              if (i < retries - 1) {
                debugPrint("Waiting ${delayMs}ms before retry...");
                await Future.delayed(Duration(milliseconds: delayMs));
                delayMs = delayMs * 2; // Exponential backoff
              }
            } catch (e, stackTrace) {
              debugPrint("Error getting token (attempt ${i + 1}): $e");
              debugPrint("StackTrace: $stackTrace");

              if (i == retries - 1) {
                // Last retry, try one more time
                try {
                  String? token = await messaging.getToken();
                  if (token != null && token.isNotEmpty) {
                    debugPrint("FCM token retrieved on final attempt: $token");
                    return token;
                  }
                } catch (finalError) {
                  debugPrint("Final attempt failed: $finalError");
                }
              } else {
                await Future.delayed(Duration(milliseconds: delayMs));
                delayMs = delayMs * 2;
              }
            }
          }

          debugPrint("Failed to get FCM token after $retries attempts");
          return "token_not_available";
        } else {
          // Android - direct token request
          String? token = await messaging.getToken();
          debugPrint("Android FCM token: $token");
          return token ?? "token_not_available";
        }
      } else {
        debugPrint(
            "Notification permission not granted: ${settings.authorizationStatus}");
        return "permission_not_granted";
      }
    } catch (e, stackTrace) {
      debugPrint("Error getting device token: $e");
      debugPrint("StackTrace: $stackTrace");
      return "error_getting_token";
    }
  }

  void isTokenRefresh() async {
    messaging.onTokenRefresh.listen((token) {
      debugPrint("FCM Token refreshed: $token");
      // You can save this token or send it to your server here
    });
  }

  // Setup token refresh listener and get initial token
  Future<String?> setupTokenListener() async {
    // Listen for token refresh
    isTokenRefresh();

    // Try to get the current token
    try {
      String? token = await messaging.getToken();
      debugPrint("Initial FCM token from listener: $token");
      return token;
    } catch (e) {
      debugPrint("Error getting initial token in listener: $e");
      return null;
    }
  }

  //handle tap on notification when app is in background or terminated
  Future<void> setupInteractMessage() async {
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    // when app is terminated
    if (initialMessage != null) {
      print("terminated state: $initialMessage");
      print("data => ${initialMessage.data.toString()}");
      handleMessage(initialMessage);
    }
    // handle tap on notification when app is in background state
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      print("background state: $message");
      print("data => ${message.data.toString()}");
      handleMessage(message);
    });
  }

  void handleMessage(RemoteMessage message) async {
    debugPrint("message => ${message.data}");

    // Check if user_id exists in the notification data
    // if (message.data["user_id"] != "") {
    //   await _checkAndRequestLocationPermission(
    //       int.parse(message.data["user_id"]));
    // }
  }
}

Future<void> enableIOSNotifications() async {
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true, // Required to display a heads up notification
    badge: true,
    sound: true,
  );
}

Future<void> _checkAndRequestLocationPermission(int userId, var action) async {
  bool locationPermissionGranted =
      await Geolocator.checkPermission() == LocationPermission.always ||
          await Geolocator.checkPermission() == LocationPermission.whileInUse;
  bool locationServiceEnabled = await Geolocator.isLocationServiceEnabled();

  if (locationPermissionGranted && locationServiceEnabled) {
    // Permissions and services are already enabled
    await _fetchAndSendLocation(userId, action);
  } else {
    // Show a dialog to guide the user
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
            'Please enable location permissions and services to proceed.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (!locationServiceEnabled) {
                Geolocator.openLocationSettings();
              } else if (!locationPermissionGranted) {
                Geolocator.openAppSettings();
              }
            },
            child: const Text('Settings'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    // Listen for changes in location services or permissions
    // Geolocator.getServiceStatusStream().listen((serviceStatus) async {
    //   if (serviceStatus == ServiceStatus.enabled) {
    //     bool permissionGranted = await Geolocator.checkPermission() ==
    //             LocationPermission.always ||
    //         await Geolocator.checkPermission() == LocationPermission.whileInUse;
    //     if (permissionGranted) {
    //       await _fetchAndSendLocation(userId);
    //     }
    //   }
    // });
    Geolocator.getServiceStatusStream().listen((ServiceStatus status) async {
      if (status == ServiceStatus.enabled) {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          await _fetchAndSendLocation(
              userId, action); // Fetch and send location once enabled
        }
      }
    });
  }
}

Future<void> _fetchAndSendLocation(int userId, var action) async {
  try {
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    // Call your API
    if (action == "activity_crm_location") {
      await crmModuleSendLocation(
          position.latitude, position.longitude, userId, action);
    } else if (action == "activity_contact_location") {
      await contactModuleSendLocation(
          position.latitude, position.longitude, userId, action);
    } else {
      await sendLocation(position.latitude, position.longitude, userId, action);
    }
    debugPrint("Location sent: ${position.latitude}, ${position.longitude}");
  } catch (e) {
    debugPrint("Error fetching location: $e");
  }
}

// Function to send location data to the API
Future<void> sendLocation(
    double latitude, double longitude, partnerId, action) async {
  final Dio dio = Dio();
  String url = '${GetStorage().read(hostUrlLoginSession)}/geo/update';
  var headers = {
    'Cookie': 'session_id=c5a7fe5af5aa4b5940c4365a1592702650a6fed8'
  };
  final Map<String, dynamic> data = {
    "latitude": latitude,
    "longitude": longitude,
    "partner_id": partnerId,
    "action": action,
  };
  print("data=> $data");
  print("URL=> ${GetStorage().read(hostUrlLoginSession)}");
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
      debugPrint("Response Data: ${json.encode(response.data)}");
    } else {
      debugPrint("Error: ${response.statusMessage}");
    }
  } catch (e) {
    debugPrint("Exception: $e");
  }
}

// Send location (CRM Module Schedule Activity)
Future<void> crmModuleSendLocation(
    double latitude, double longitude, partnerId, action) async {
  final Dio dio = Dio();
  String url =
      '${GetStorage().read(hostUrlLoginSession)}/geo/activity/crm/update';
  var headers = {
    'Cookie': 'session_id=c5a7fe5af5aa4b5940c4365a1592702650a6fed8'
  };
  final Map<String, dynamic> data = {
    "latitude": latitude,
    "longitude": longitude,
    "partner_id": partnerId,
    "action": action,
  };
  print("data=> $data");
  print("URL=> ${GetStorage().read(hostUrlLoginSession)}");
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
      debugPrint("Response Data: ${json.encode(response.data)}");
    } else {
      debugPrint("Error: ${response.statusMessage}");
    }
  } catch (e) {
    debugPrint("Exception: $e");
  }
}

// Send location (CRM Module Schedule Activity)
Future<void> contactModuleSendLocation(
    double latitude, double longitude, partnerId, action) async {
  final Dio dio = Dio();
  String url =
      '${GetStorage().read(hostUrlLoginSession)}/geo/activity/contact/update';
  var headers = {
    'Cookie': 'session_id=c5a7fe5af5aa4b5940c4365a1592702650a6fed8'
  };
  final Map<String, dynamic> data = {
    "latitude": latitude,
    "longitude": longitude,
    "partner_id": partnerId,
    "action": action,
  };
  print("data=> $data");
  print("URL=> ${GetStorage().read(hostUrlLoginSession)}");
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
      debugPrint("Response Data: ${json.encode(response.data)}");
    } else {
      debugPrint("Error: ${response.statusMessage}");
    }
  } catch (e) {
    debugPrint("Exception: $e");
  }
}

// import 'dart:math';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'dashboard.dart';

// class NotificationServices {
//   //initialising firebase message plugin
//   final FirebaseMessaging messaging = FirebaseMessaging.instance;

//   final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
//       FlutterLocalNotificationsPlugin();

//   // function to request notifications permissions
//   void requestNotificationPermission() async {
//     NotificationSettings settings = await messaging.requestPermission(
//         alert: true,
//         announcement: true,
//         badge: true,
//         carPlay: true,
//         criticalAlert: true,
//         provisional: true,
//         sound: true);

//     if (settings.authorizationStatus == AuthorizationStatus.authorized) {
//       //user granted permission
//     } else if (settings.authorizationStatus ==
//         AuthorizationStatus.provisional) {
//       //user granted provisional permission
//     } else {
//       // AppSettings.openNotificationSettings();
//       //user denied permission
//     }
//   }

//   // function to initialise flutter local notification plugin to show notifications for android when app is active
//   void initLocalNotifications(
//       BuildContext context, RemoteMessage message) async {
//     var androidInitializationSettings =
//         const AndroidInitializationSettings('@mipmap/ic_launcher');
//     var iosInitializationSettings = const DarwinInitializationSettings();

//     var initializationSetting = InitializationSettings(
//         android: androidInitializationSettings, iOS: iosInitializationSettings);

//     await _flutterLocalNotificationsPlugin.initialize(initializationSetting,
//         onDidReceiveNotificationResponse: (payload) {
//       handleMessage(message);
//     });
//   }

//   void firebaseInit(BuildContext context) {
//     FirebaseMessaging.onMessage.listen((message) {
//       debugPrint("message => ${message.data}");
//       initLocalNotifications(context, message);
//       enableIOSNotifications();
//       showNotification(message);
//     });
//   }

//   // function to show visible notification when app is active
//   Future<void> showNotification(RemoteMessage message) async {
//     AndroidNotificationChannel channel = AndroidNotificationChannel(
//         Random.secure().nextInt(100000).toString(),
//         'High Importance Notifications',
//         importance: Importance.max);

//     AndroidNotificationDetails androidNotificationDetails =
//         AndroidNotificationDetails(
//             channel.id.toString(), channel.name.toString(),
//             channelDescription: 'your channel description',
//             importance: Importance.high,
//             priority: Priority.high);

//     const DarwinNotificationDetails darwinNotificationDetails =
//         DarwinNotificationDetails(
//             presentAlert: true, presentBadge: true, presentSound: true);

//     NotificationDetails notificationDetails = NotificationDetails(
//         android: androidNotificationDetails, iOS: darwinNotificationDetails);
//     print("object show : ${message.data}");
//     Future.delayed(Duration.zero, () {
//       _flutterLocalNotificationsPlugin.show(
//           0,
//           message.notification!.title.toString(),
//           message.notification!.body.toString(),
//           notificationDetails);
//     });
//   }

//   //handle tap on notification when app is in background or terminated
//   Future<void> setupInteractMessage() async {
//     RemoteMessage? initialMessage =
//         await FirebaseMessaging.instance.getInitialMessage();
//     // when app is terminated
//     if (initialMessage != null) {
//       debugPrint("setupInteractMessage terminated state: $initialMessage");
//       handleMessage(initialMessage);
//     } else {
//       // handle tap on notification when app is in background state
//       FirebaseMessaging.onMessageOpenedApp.listen((message) {
//         debugPrint("setupInteractMessage background state: $message");
//         handleMessage(message);
//       });
//     }
//   }

//   void handleMessage(RemoteMessage message) {
//     debugPrint("handleMessage => ${message.data}");
//     if (message.data["redirect"] != "") {
//       debugPrint("message redirect=> ${message.data["redirect"]}");
//       navigateToUrl(message.data["redirect"]);
//     }
//   }
// }

// Future<void> enableIOSNotifications() async {
//   await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
//     alert: true,
//     badge: true,
//     sound: true,
//   );
// }

// Future<void> navigateToUrl(String url) async {
//   if (webViewController != null) {
//     // await webViewController!
//     //     .loadUrl(urlRequest: URLRequest(url: WebUri.uri(Uri.parse(url))));
//     DashboardScreen(
//       webHostUrl: url,
//     );
//   }
// }
