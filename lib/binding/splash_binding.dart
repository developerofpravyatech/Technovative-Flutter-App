import 'package:get/get.dart';
import '../controller/login_controller.dart';
import '../controller/splash_controller.dart';


class SplashBinding extends Bindings {
  @override
  void dependencies() {
    // Use lazy initialization - dependencies will be created when first accessed
    // GetX will automatically resolve dependencies when controllers are created
    Get.lazyPut<SplashController>(
      () => SplashController(Get.find()),
      fenix: true,
    );
    
    Get.lazyPut<LoginController>(
      () => LoginController(Get.find(), Get.find(), Get.find()),
      fenix: true,
    );
  }
}
