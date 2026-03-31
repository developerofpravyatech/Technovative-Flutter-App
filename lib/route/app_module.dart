import 'package:get/route_manager.dart';
import 'package:teknovative_solution/dashboard.dart';
import 'package:teknovative_solution/login.dart';
import '../binding/dashboard_binding.dart';
import '../binding/login_binding.dart';
import '../splash_screen.dart';
import '../binding/splash_binding.dart';
import 'route.dart';

class AppPage {
  AppPage._();

  static final routes = [
    GetPage(name: AppRoute.splash, page: () => const SplashSCreen(), binding: SplashBinding()),
     
    //Auth
    GetPage(name: AppRoute.login, page: () => const LoginScreen(), binding: LoginBinding()),

    //Home
    GetPage(name: AppRoute.home, page: () => DashboardScreen(), binding: DashboardBinding()),
     ];
}
