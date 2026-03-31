// import 'package:permission_handler/permission_handler.dart';
//
// class CheckPermission {
//   isStoragePermission() async {
//     //Permission.storage.request();
//     var isStorage = await Permission.manageExternalStorage.status;
//     if (!isStorage.isGranted) {
//       await Permission.manageExternalStorage.request();
//       if (!isStorage.isGranted) {
//         return false;
//       } else {
//         return true;
//       }
//     } else {
//       return true;
//     }
//   }
// }