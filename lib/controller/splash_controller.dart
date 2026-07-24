import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:teknovative_solution/dashboard.dart';
import 'package:teknovative_solution/resources/session_string.dart';
import 'package:teknovative_solution/shared/get_storage_repository.dart';
import 'package:teknovative_solution/shared/odoo_web_auth.dart';

import '../route/route.dart';
import '../shared/common/state_status.dart';

class SplashController extends GetxController
    with GetSingleTickerProviderStateMixin {
  GetStorageRepository storageRepository;
  SplashController(this.storageRepository);

  late AnimationController animation;
  late Animation<double> fadeInFadeOut;

  final _stateStatusRx = Rx<StateStatus>(StateStatus.INITIAL);
  StateStatus get stateStatus => _stateStatusRx.value;
  static SplashController get to => Get.find();

  @override
  void onInit() {
    super.onInit();
    animation =
        AnimationController(vsync: this, duration: const Duration(seconds: 3));
    fadeInFadeOut = Tween<double>(begin: 0.2, end: 1).animate(animation);
    animation.forward();
  }

  @override
  void onReady() {
    super.onReady();
    _launchPage();
    //getSpInfo();
  }

  _launchPage() async {
    await Future.delayed(const Duration(seconds: 3));
    final isLoggedIn = storageRepository.hasData(isLoginSession) &&
        storageRepository.read(isLoginSession) == true;
    if (isLoggedIn) {
      final storedHost = storageRepository.read(hostUrlLoginSession)?.toString();
      final login = storageRepository.read(userNameSession)?.toString();
      final password = storageRepository.read(userPass)?.toString();
      final db = storageRepository.read(odooDbSession)?.toString();

      String? webHostUrl = storageRepository.read(whostUrl)?.toString();

      // Refresh Odoo web session so cold start stays single-login.
      if (storedHost != null &&
          storedHost.isNotEmpty &&
          login != null &&
          password != null &&
          db != null &&
          db.isNotEmpty) {
        final sessionId = await OdooWebAuth.authenticate(
          hostUrl: storedHost,
          db: db,
          login: login,
          password: password,
        );
        if (sessionId != null && sessionId.isNotEmpty) {
          await storageRepository.write(odooSessionId, sessionId);
        }
        webHostUrl = '$storedHost/web';
        await storageRepository.write(whostUrl, webHostUrl);
      }

      Get.offAll(DashboardScreen(
        webHostUrl: webHostUrl,
      ));
    } else {
      Get.offAllNamed(AppRoute.login);
    }
  }
}
