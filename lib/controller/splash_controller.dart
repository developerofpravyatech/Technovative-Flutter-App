import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:teknovative_solution/dashboard.dart';
import 'package:teknovative_solution/resources/session_string.dart';
import 'package:teknovative_solution/shared/get_storage_repository.dart';

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
    await Future.delayed(const Duration(seconds: 3)).then((value) {
      final isLoggedIn = storageRepository.hasData(isLoginSession) &&
          storageRepository.read(isLoginSession) == true;
      if (isLoggedIn) {
        Get.offAll(DashboardScreen(
          webHostUrl: storageRepository.read(whostUrl),
        ));
      } else {
        Get.offAllNamed(AppRoute.login);
      }
    });
  }
}
