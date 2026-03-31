import 'dart:io';

import 'package:flutter/material.dart';
import 'package:teknovative_solution/resources/color.dart';
import 'package:teknovative_solution/resources/constants.dart';

/// Prominent disclosure dialog required by Google Play for background location access.
/// Must be shown in-app, right before requesting ACCESS_BACKGROUND_LOCATION permission.
/// See: https://support.google.com/googleplay/android-developer/answer/11150561
class BackgroundLocationDisclosure {
  /// Shows the prominent disclosure dialog and returns:
  /// - true if user tapped "Allow" (proceed to request permission)
  /// - false if user tapped "Not Now" (do not request, can ask again later)
  static Future<bool> show(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BackgroundLocationDisclosureDialog(),
    );
    return result ?? false;
  }
}

class _BackgroundLocationDisclosureDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: whiteBGColor,
      shape: RoundedRectangleBorder(borderRadius: borderRadius17),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.location_on,
                size: 48,
                color: primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Location access for tracking',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Teknovative Solution uses your location in the background to provide '
                'live location tracking. This helps share your location with your team '
                'when you are out in the field, even when the app is not open.\n\n'
                'Your location data is only used for this purpose and is sent securely '
                'to your organization\'s servers.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: blackColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: borderRadius17,
                    ),
                  ),
                  child: const Text('Allow'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Not Now',
                  style: TextStyle(
                    fontSize: 16,
                    color: textColorGreyDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
