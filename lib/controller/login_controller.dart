import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../dashboard.dart';
import '../resources/extension.dart';
import '../resources/session_string.dart';
import '../shared/api_repository.dart';
import '../shared/get_storage_repository.dart';
import '../shared/network_info.dart';
import '../shared/odoo_web_auth.dart';
import '../shared/common/state_status.dart';

class LoginController extends GetxController {
  ApiRepository apiRepository;
  GetStorageRepository storageRepository;
  NetworkInfo networkInfo;

  LoginController(this.apiRepository, this.storageRepository, this.networkInfo);

  final _stateStatusRx = Rx<StateStatus>(StateStatus.INITIAL);
  StateStatus get stateStatus => _stateStatusRx.value;

  RxString hostString = "https://".obs;
  var hostStringList = Rx<List<String>>(["http://", "https://"]);
  RxString database = "".obs;
  RxList databaseList = RxList([]);
  RxBool showPass = true.obs;

  late FocusNode urlFocus, passFocus, userFocus, dbFocus;

  late TextEditingController urlController,
      dbController,
      userController,
      passController;
  DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
  final firebaseMessaging = FirebaseMessaging.instance;

  @override
  void onInit() {
    super.onInit();
    // getDeviceInfo();
    urlController = TextEditingController();
    userController = TextEditingController();
    passController = TextEditingController();
    userFocus = FocusNode();
    dbFocus = FocusNode();
    urlFocus = FocusNode();
    passFocus = FocusNode();
  }

  void loginApiCall() {
    if (_stateStatusRx.value == StateStatus.LOADING) {
      return;
    }

    networkInfo.isConnected().then((value) async {
      if (value) {
        _stateStatusRx.value = StateStatus.LOADING;
        String? fCMToken;

        // Request notification permissions and get FCM token with error handling
        try {
          // Request notification permissions first (required for iOS)
          final settings = await firebaseMessaging.requestPermission(
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

          // Only get token if permission is granted or provisional
          if (settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional) {
            // Use a more reliable method to get token with retries
            fCMToken = await _getTokenWithRetry();
            debugPrint("fCMToken: $fCMToken");
          } else {
            debugPrint(
                "Notification permission not granted, using fallback token");
            fCMToken = null;
          }
        } catch (e, stackTrace) {
          debugPrint("Error getting FCM token: $e");
          debugPrint("StackTrace: $stackTrace");
          // Continue with login even if token fails
          fCMToken = null;
        }

        showSnackbar('Loging in ... ', '');
        // if (!fieldValidation()) {
        //   _stateStatusRx.value = StateStatus.INITIAL;
        //   return;
        // }
        var hostUrl = "$hostString${urlController.text.trim()}";

        apiRepository.getApi("$hostUrl/users", queryParameters: {
          "login": userController.text.trim(),
          "player_id": (fCMToken?.trim() ?? "123"),
          "password": passController.text.trim()
        }, headers: {
          'Cookie': 'session_id=c5a7fe5af5aa4b5940c4365a1592702650a6fed8'
        }, success: (response) async {
          // Keep LOADING until navigation (includes Odoo web session auth).
          debugPrint("================ LOGIN API SUCCESS RESPONSE ================");
          debugPrint(response.toString());
          debugPrint("============================================================");
          dynamic res = jsonDecode(response.toString());
          if (res['responseCode'] == 200) {
            GetStorageRepository gs = GetStorageRepository(Get.find());
            final login = userController.text.trim();
            final password = passController.text.trim();
            await gs.write(isLoginSession, true);
            await gs.write(userNameSession, login);
            await gs.write(userPass, password);
            await gs.write(userIdSession, res["data"]["userId"]);
            await gs.write(hostUrlLoginSession, hostUrl);

            // Resolve DB from API (needed for Odoo web session auth).
            String? db;
            final dbList = res["data"]?["db_list"];
            if (dbList is List && dbList.isNotEmpty) {
              db = dbList.first.toString();
            }
            db ??= database.value.isNotEmpty ? database.value : null;
            if (db != null) {
              await gs.write(odooDbSession, db);
            }

            // Create a real Odoo web session so WebView opens already logged in.
            String? sessionId = await OdooWebAuth.authenticate(
              hostUrl: hostUrl,
              db: db ?? '',
              login: login,
              password: password,
            );
            if (sessionId != null && sessionId.isNotEmpty) {
              await gs.write(odooSessionId, sessionId);
            }

            final webUrl = '$hostUrl/web';
            await gs.write(whostUrl, webUrl);

            debugPrint(
                "object web url = $webUrl | session=${sessionId != null}");
            _stateStatusRx.value = StateStatus.SUCCESS;
            await Get.offAll(DashboardScreen(webHostUrl: webUrl));
          } else {
            _stateStatusRx.value = StateStatus.FAILURE;
            showErrorSnackbar(res["responseMessage"]);
          }
        }, error: (e) {
          debugPrint("================ LOGIN API ERROR RESPONSE ================");
          debugPrint("Error: ${e?.message}");
          debugPrint("==========================================================");
          _stateStatusRx.value = StateStatus.FAILURE;
          Get.showErrorSnackbar(e!.message);
        });
      } else {
        _stateStatusRx.value = StateStatus.FAILURE;
        Get.showErrorSnackbar('No internet connect');
      }
    });
  }

  getDatabaseList() {
    print("object");
    _stateStatusRx.value = StateStatus.LOADING;
    var hostUrl = "$hostString${urlController.text.trim()}";
    apiRepository.getApi("$hostUrl/db", headers: {
      'Cookie': 'session_id=c5a7fe5af5aa4b5940c4365a1592702650a6fed8'
    }, success: (response) async {
      _stateStatusRx.value = StateStatus.SUCCESS;
      //var result = LoginResponseEntity.fromJson(response);
      dynamic res = jsonDecode(response.toString());
      if (res['responseCode'] == 200) {
        databaseList.value = res['data']['db_list'];
        // if(res['data']['db_list'] != []){
        //   List<String> data=[];
        //   for (var element in res['data']['db_list']) {
        //     data.add(element.toString());
        //   }

        //databaseList.value = data;
        //}
        debugPrint("Database list : $databaseList");
      } else {
        showErrorSnackbar(res["responseMessage"]);
      }
    }, error: (e) {
      _stateStatusRx.value = StateStatus.FAILURE;
      Get.showErrorSnackbar(e!.message);
    });
  }

  Future<void> getDeviceInfo() async {
    try {
      // Request notification permissions first
      final settings = await firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final fCMToken = await firebaseMessaging.getToken();
        debugPrint("Device token : $fCMToken");
      } else {
        debugPrint("Notification permission not granted");
      }
    } catch (e) {
      debugPrint("Error getting device token: $e");
    }

    // NotificationSettings settings = await firebaseMessaging.requestPermission(
    //     alert: true,
    //     announcement: false,
    //     badge: true,
    //     carPlay: false,
    //     criticalAlert: false,
    //     provisional: false,
    //     sound: true);
    //   await Permission.notification.request();
    //iosInfo = await deviceInfoPlugin.iosInfo;
    // FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    //   print('Got a message whilst in the foreground!');
    //   print('Message data: ${message.data}');

    //   if (message.notification != null) {
    //     print('Message also contained a notification: ${message.notification}');
    //   }
    // });
  }

  // Helper method to get token with retry logic
  Future<String?> _getTokenWithRetry({int maxRetries = 5}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        String? token = await firebaseMessaging.getToken();
        if (token != null && token.isNotEmpty) {
          debugPrint("Token retrieved successfully on attempt ${i + 1}");
          return token;
        }
        debugPrint("Token is null or empty on attempt ${i + 1}");
      } catch (e) {
        debugPrint("Error getting token (attempt ${i + 1}): $e");
      }

      // Wait before retrying (exponential backoff)
      if (i < maxRetries - 1) {
        int delayMs = 1000 * (i + 1); // 1s, 2s, 3s, 4s
        debugPrint("Waiting ${delayMs}ms before retry...");
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    debugPrint("Failed to get token after $maxRetries attempts");
    return null;
  }
}
