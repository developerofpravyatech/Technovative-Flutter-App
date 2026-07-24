import 'package:get/get.dart';
import 'package:teknovative_solution/dashboard.dart';

class DashboardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => const DashboardScreen());
  }
}
