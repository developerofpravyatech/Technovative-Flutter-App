import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/splash_controller.dart';

class SplashSCreen extends GetView<SplashController> {
  const SplashSCreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade50,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
          child: FadeTransition(
            opacity: controller.fadeInFadeOut,
            child: TweenAnimationBuilder(
              tween: Tween<double>(
                  begin: 0.0, end: 1.0), // start size and zoom-out scale factor
              duration:
                  const Duration(seconds: 2), // adjust the duration as needed
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: child,
                );
              },
              child: Image.asset("assets/main_company_logo.png"),
            ),
          ),
        ),
      ),
    );
  }
}
