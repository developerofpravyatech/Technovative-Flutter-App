# Technovative Flutter App

Flutter mobile app for **Technovative / PravyaTech**, wrapping the Odoo CRM web experience in a native shell with login, WebView dashboard, Firebase messaging, and location services.

Repository: [Technovative-Flutter-App](https://github.com/developerofpravyatech/Technovative-Flutter-App)

## Features

- Flutter login against the hosted Odoo `/users` API
- Single-login WebView session via Odoo `/web/session/authenticate` + cookie injection (Android & iOS)
- In-app WebView dashboard (`flutter_inappwebview`)
- Firebase Cloud Messaging
- Background / foreground location support (Android)

## Requirements

- Flutter SDK (3.x recommended)
- Xcode (for iOS)
- Android Studio / Android SDK (for Android)
- CocoaPods (iOS)

## Getting started

```bash
git clone https://github.com/developerofpravyatech/Technovative-Flutter-App.git
cd Technovative-Flutter-App
flutter pub get
cd ios && pod install && cd ..
flutter run
```

### iOS

```bash
flutter run -d <ios-device-id>
```

### Android

```bash
flutter run -d <android-device-id>
```

## Project structure

| Path | Description |
|------|-------------|
| `lib/login.dart` | Flutter login UI |
| `lib/controller/login_controller.dart` | Login API + Odoo web session |
| `lib/shared/odoo_web_auth.dart` | Odoo `/web/session/authenticate` helper |
| `lib/dashboard.dart` | WebView dashboard + cookie injection |
| `lib/controller/splash_controller.dart` | Cold-start session refresh |

## Version

Current app version is defined in `pubspec.yaml` (`1.0.5+5`).

## License

Private / proprietary — PravyaTech / Technovative.
