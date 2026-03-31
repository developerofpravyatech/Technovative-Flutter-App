import 'package:connectivity_plus/connectivity_plus.dart';

// For checking internet connectivity
abstract class NetworkInfo {
  Future<bool> isConnected();

  Future<List<ConnectivityResult>> get connectivityResult;

  Stream<List<ConnectivityResult>> get onConnectivityChanged;
}

class NetworkInfoImpl implements NetworkInfo {
  Connectivity connectivity;

  NetworkInfoImpl(this.connectivity) {
    connectivity = connectivity;
  }

  ///checks internet is connected or not
  ///returns [true] if internet is connected
  ///else it will return [false]
  @override
  Future<bool> isConnected() async {
    final result = await connectivity.checkConnectivity();
    if (result.isNotEmpty && !result.contains(ConnectivityResult.none)) {
      return true;
    }
    return false;
  }

  // TO CHECK TYPE OF INTERNET CONNECTIVITY
  @override
  Future<List<ConnectivityResult>> get connectivityResult async {
    return connectivity.checkConnectivity();
  }

  // CHECK THE TYPE ON INTERNET CONNECTION ON CHANGED OF INTERNET CONNECTION
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      connectivity.onConnectivityChanged;
}
