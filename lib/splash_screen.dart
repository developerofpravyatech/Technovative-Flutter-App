import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/splash_controller.dart';
import 'shared/common/image_constant.dart';

class SplashSCreen extends GetView<SplashController> {
  const SplashSCreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: FadeTransition(
            opacity: controller.fadeInFadeOut,
            child: TweenAnimationBuilder(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(seconds: 2),
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: child,
                );
              },
              child: Image.asset(
                ImageConstant.splashLogo,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
