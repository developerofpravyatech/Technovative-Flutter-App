
import 'package:get_storage/get_storage.dart';
//import 'package:rklawfirm/model/user_profile.dart';
//import '../../resources/session_string.dart';
import 'get_storage_provider.dart';

class GetStorageRepository implements GetStorageProvider {

  static const token = "token";

  final GetStorage _getStorage;

  GetStorageRepository(this._getStorage);

  @override
  Future<void> erase() {
    return _getStorage.erase();
  }

  @override
  T read<T>(String key) {
    return _getStorage.read(key);
  }

  @override
  bool hasData(String key) {
    return _getStorage.hasData(key);
  }

  @override
  Future<void> remove(String key) {
    return _getStorage.remove(key);
  }

  @override
  Future<void> write(String key, value) {
    return _getStorage.write(key, value);
  }

  @override
  Future<void> writeIfNull(String key, value) {
    return _getStorage.writeIfNull(key, value);
  }

  @override
  void writeInMemory(String key, value) {
    _getStorage.writeInMemory(key, value);
  }

  // ProfileData? getUserData(){
  //   if(hasData(tokenKey)) {
  //     return ProfileData?.fromJson(read(tokenKey));
  //   }
  //   return null;
  // }
}
