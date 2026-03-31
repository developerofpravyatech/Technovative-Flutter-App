import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'color.dart';
import 'constants.dart';

class Themes {
  Themes._();

  static ThemeData getTheme(BuildContext context) {
    return ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xff1F3844),
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
        cardColor: Colors.white,
        cardTheme: const CardThemeData(surfaceTintColor: Colors.white),
        textSelectionTheme:
            TextSelectionThemeData(cursorColor: buttonColorRed2),
        textTheme: GoogleFonts.dmSansTextTheme(),
        // inputDecorationTheme: InputDecorationTheme(
        //     enabledBorder: OutlineInputBorder(
        //         borderSide: BorderSide(color: primaryColor),
        //         borderRadius: BorderRadius.circular(33)),
        //     hintStyle: TextStyle(
        //         color: textColorGreyDark,
        //         fontSize: 13,
        //         fontWeight: FontWeight.w500),
        //     border: OutlineInputBorder(
        //         borderRadius: BorderRadius.circular(33),
        //         borderSide: BorderSide(color: primaryColor)),
        //     errorBorder: OutlineInputBorder(
        //         borderRadius: BorderRadius.circular(33),
        //         borderSide: BorderSide(color: primaryColor)),
        //     focusedErrorBorder: OutlineInputBorder(
        //         borderRadius: BorderRadius.circular(33),
        //         borderSide: BorderSide(color: primaryColor)),
        //     focusedBorder: OutlineInputBorder(
        //         borderRadius: BorderRadius.circular(33),
        //         borderSide: BorderSide(color: primaryColor)),
        //     filled: true,
        //     fillColor: Colors.white,
        //     contentPadding: const EdgeInsets.fromLTRB(15, 13, 15, 13)),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: const WidgetStatePropertyAll(Color(0xffFFFFFF)),
            textStyle: const WidgetStatePropertyAll(TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500)),
            backgroundColor: WidgetStatePropertyAll(primaryColor),
            // shape: MaterialStatePropertyAll(RoundedRectangleBorder(
            //     borderRadius: BorderRadius.circular(8)))
          ),
        ),
        appBarTheme: const AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.white,
                statusBarBrightness: Brightness.light,
                statusBarIconBrightness: Brightness.dark),
            elevation: 0));
  }

  static TextStyle getTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: Constants.APP_FONT_SIZE_REGULAR,
        );
  }

  static TextStyle getTextStyleRegulerWhite(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: Constants.APP_FONT_SIZE_REGULAR,
          color: Constants.COLOR_APP_WHITE,
        );
  }

  static TextStyle getTextStyleSmall(BuildContext context) {
    return getTextStyle(context).copyWith(
      fontSize: Constants.APP_FONT_SIZE_10,
    );
  }

  static TextStyle getTextStyleWhite(BuildContext context) {
    return getTextStyle(context).copyWith(color: Constants.COLOR_TEXT_WHITE);
  }

  static TextStyle getTextStyleBoldWhite(BuildContext context) {
    return getTextStyleBold(context).copyWith(
      color: Constants.COLOR_TEXT_WHITE,
    );
  }

  static TextStyle getTextStyleBold(BuildContext context) {
    return getTextStyle(context).copyWith(fontWeight: FontWeight.w600);
  }

  static TextStyle getTextStyleBoldRed(BuildContext context) {
    return getTextStyle(context)
        .copyWith(fontWeight: FontWeight.bold, color: textColorRed);
  }
}
