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

import 'doze_mode_service.dart';
import 'shared/background_location_disclosure.dart';
import 'shared/common/image_constant.dart';

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
  bool isServiceStarted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start the background service
    sendUserIdToNative();
    checkServiceAndGpsStatus();
    startBackgroundService();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DozeModeService.stopListening();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    DozeModeService.handleLifecycleChange(state);
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
    startLocationService();
    if (mounted) setState(() => isServiceStarted = true);
  }

  void startLocationService() {
    if (!Platform.isAndroid) {
      debugPrint("startLocationService: Skipped on non-Android platform");
      return;
    }

    try {
      const platform = MethodChannel('com.pravyatech.dozeMode');
      platform.invokeMethod('startService');
      DozeModeService.startListening();
    } on MissingPluginException catch (e) {
      debugPrint('Method channel not found: ${e.message}');
      debugPrint('Rebuild the app after package name change');
    } catch (e) {
      debugPrint('Error starting location service: $e');
    }
  }

  void stopLocationService() {
    if (!Platform.isAndroid) {
      debugPrint("stopLocationService: Skipped on non-Android platform");
      return;
    }

    try {
      const platform = MethodChannel('com.pravyatech.dozeMode');
      platform.invokeMethod('stopService');
      DozeModeService.stopListening();
    } on MissingPluginException catch (e) {
      debugPrint('Method channel not found: ${e.message}');
    } catch (e) {
      debugPrint('Error stopping location service: $e');
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
                      }, bWidth: 120, color: Color(0xff024950)),
                      whiteButton("OK", () {
                        Navigator.pop(Get.context!, true);
                      }, bWidth: 120),
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

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Color(0xff024950),
        statusBarIconBrightness: Brightness.light));
    return SafeArea(
      child: UpgradeAlert(
        upgrader: Upgrader(
            //dialogStyle: UpgradeDialogStyle.material,
            durationUntilAlertAgain: const Duration(days: 1)),
        child: WillPopScope(
          onWillPop: () async {
            return (await showConfirmationDialog()) == true;
          },
          child: Scaffold(
              appBar: AppBar(
                toolbarHeight: 30,
                backgroundColor: const Color(0xff024950),
                actions: [
                  InkWell(
                    onTap: () async {
                      if (isServiceStarted) {
                        stopLocationService();
                        setState(() {
                          isServiceStarted = false;
                        });
                      } else {
                        bool gpsEnabled = false;
                        try {
                          gpsEnabled =
                              await Geolocator.isLocationServiceEnabled();
                        } catch (e) {
                          debugPrint('Error checking GPS status: $e');
                        }
                        if (gpsEnabled) {
                          await _ensureBackgroundLocationAndStart();
                        } else {
                          // Show dialog or snackbar if GPS is not enabled
                          Get.snackbar('GPS Required',
                              'Please enable GPS to start tracking.',
                              snackPosition: SnackPosition.BOTTOM);
                        }
                      }
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            isServiceStarted
                                ? Icons.location_off_sharp
                                : Icons.location_on_sharp,
                            color: isServiceStarted ? Colors.red : Colors.green,
                            size: 18,
                          ),
                          onPressed: () async {
                            if (isServiceStarted) {
                              stopLocationService();
                              setState(() {
                                isServiceStarted = false;
                              });
                            } else {
                              bool gpsEnabled = false;
                              try {
                                gpsEnabled =
                                    await Geolocator.isLocationServiceEnabled();
                              } catch (e) {
                                debugPrint('Error checking GPS status: $e');
                              }
                              if (gpsEnabled) {
                                await _ensureBackgroundLocationAndStart();
                              } else {
                                Get.snackbar('GPS Required',
                                    'Please enable GPS to start tracking.',
                                    snackPosition: SnackPosition.BOTTOM);
                              }
                            }
                          },
                        ),
                        Text(
                          isServiceStarted ? "Stop Tracking" : "Start Tracking",
                          style: Themes.getTextStyleBoldWhite(context)
                              .copyWith(fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                ],
              ),
              body: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: InAppWebView(
                          onWebViewCreated: (controller) {
                            webViewController = controller;
                            if (widget.webHostUrl != null) {
                              controller.loadUrl(
                                  urlRequest: URLRequest(
                                      url: WebUri.uri(
                                          Uri.parse(widget.webHostUrl!))));
                            }
                          },
                          shouldOverrideUrlLoading:
                              (controller, navigationAction) async {
                            var uri = navigationAction.request.url!;
                            debugPrint(
                                "url = > ${navigationAction.request.url}");
                            if (uri.scheme == 'tel') {
                              await launchUrl(uri);
                              return NavigationActionPolicy.CANCEL;
                            } else if (uri.scheme == 'whatsapp') {
                              await launchUrl(uri);
                              return NavigationActionPolicy.CANCEL;
                            } else if (uri.scheme == 'mailto') {
                              await launchUrl(uri);
                              return NavigationActionPolicy.CANCEL;
                            } else if (uri.host == 'maps.google.com' &&
                                uri.queryParameters.containsKey('q')) {
                              // Handle Google Maps URL
                              final location = uri.queryParameters['q'];
                              if (location != null) {
                                await openGoogleMapsUsingAddress(
                                    "https://www.google.com/maps/search/?api=1&query=$location");
                                return NavigationActionPolicy.CANCEL;
                              }
                            } else if (uri.path.contains('/maps/dir/')) {
                              // Case 2a: Multiple locations (directions URL)
                              print(
                                  "Opening Google Maps Directions externally");
                              final Uri googleMapsUrl = uri;
                              if (await canLaunchUrl(googleMapsUrl)) {
                                await launchUrl(googleMapsUrl,
                                    mode: LaunchMode.externalApplication);
                              } else {
                                print("Could not launch $googleMapsUrl");
                              }

                              return NavigationActionPolicy.CANCEL;
                            }
                            return NavigationActionPolicy.ALLOW;
                          },
                          onDownloadStartRequest:
                              (controller, downloadStartRequest) {
                            print(
                                "url => ${downloadStartRequest.url.uriValue}");
                            getPDF(context,
                                "${downloadStartRequest.url.uriValue}");
                          },
                          onLoadStart: (controller, url) {
                            debugPrint("WebView started loading: $url");
                            setState(() => contentLLoading = true);
                          },
                          onLoadStop: (controller, url) {
                            debugPrint("WebView finished loading: $url");
                            setState(() => contentLLoading = false);
                          },
                          onReceivedError: (controller, request, error) {
                            debugPrint("WebView error: ${error.description}");
                            debugPrint("Error code: ${error.toString()}");
                            debugPrint("Failed URL: ${request.url}");
                            setState(() => contentLLoading = false);
                            Get.snackbar(
                              'Loading Error',
                              'Failed to load page: ${error.description}',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                          },
                          onReceivedHttpError: (controller, request, response) {
                            debugPrint(
                                "WebView HTTP error: ${response.statusCode}");
                            debugPrint("Failed URL: ${request.url}");
                            setState(() => contentLLoading = false);
                            Get.snackbar(
                              'HTTP Error',
                              'HTTP ${response.statusCode}: ${response.reasonPhrase}',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                          },
                          initialUrlRequest: URLRequest(
                              url: WebUri.uri(Uri.parse(widget.webHostUrl!))),
                          initialSettings: InAppWebViewSettings(
                              enableViewportScale: true,
                              javaScriptEnabled: true,
                              pageZoom: 1,
                              supportZoom: false,
                              initialScale: 1,
                              useShouldOverrideUrlLoading: true,
                              transparentBackground: true,
                              verticalScrollBarEnabled: false,
                              allowsLinkPreview: true,
                              allowsInlineMediaPlayback: true,
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
              )),
        ),
      ),
    );
  }
}
