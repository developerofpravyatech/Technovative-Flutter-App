// ignore_for_file: constant_identifier_names

import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:teknovative_solution/resources/color.dart';

abstract class Constants {
  Constants._();

  static const somethingWentWrong = "Something went wrong",
      noInteretConnection = "No Internet Connectoin";
  static const failCode = 0;
  static const failInternetCode = -1;
  static const failSomethingWentWrongCode = -2;

  static const Color COLOR_ICON_GREY = Colors.grey;

  static const Color COLOR_DIVIDER = COLOR_APP_GREY;
  static const Color COLOR_APP_GREY = Colors.grey;
  static const Color COLOR_APP_GREEN = Colors.green;
  static const Color COLOR_APP_RED = Colors.red;

  static const Color COLOR_APP_BLACK = Colors.black;
  static const Color COLOR_APP_WHITE = Colors.white;
  static const Color COLOR_ICON_WHITE = COLOR_APP_WHITE;
  static const Color COLOR_ICON_BLACK = COLOR_APP_BLACK;
  static const Color COLOR_TEXT_WHITE = COLOR_APP_WHITE;

  static const Color COLOR_APP_TRANSPARENT = Colors.transparent;

  static const Color COLOR_APP_SEMI_TRANSPARENT = Color.fromRGBO(0, 0, 0, 0.5);

  // FONT
  static const APP_FONT_SIZE_REGULAR = 16.0;
  static const APP_FONT_SIZE_10 = 10.0;
  static const APP_FONT_SIZE_EXTRA_LARGE = 20.0;
  //PADDING
  static const APP_PADDING = 12.0;
}

FontWeight fwt100 = FontWeight.w100,
    fwt200 = FontWeight.w200,
    fwt300 = FontWeight.w300,
    fwt400 = FontWeight.w400,
    fwt500 = FontWeight.w500,
    fwt600 = FontWeight.w600,
    fwt700 = FontWeight.w700,
    fwt800 = FontWeight.w800;

BorderRadius borderRadius13 = BorderRadius.circular(13);
BorderRadius borderRadius15 = BorderRadius.circular(15);
BorderRadius borderRadius17 = BorderRadius.circular(17);
BorderRadius borderRadius20 = BorderRadius.circular(20);
BorderRadius borderRadius25 = BorderRadius.circular(25);
BorderRadius borderRadius28 = BorderRadius.circular(28);

//Color(0xffE9E1F4)
Widget divider(
    {Color? color, double? thickness, double? indent, double? endIndent}) {
  return Divider(
      color: color ?? colorText1,
      thickness: thickness ?? 1,
      indent: indent ?? 5,
      endIndent: endIndent ?? 5);
}

Widget verticalDivider({double? startindent, double? endindent, Color? color}) {
  return VerticalDivider(
    thickness: 0.6,
    width: 8,
    indent: startindent ?? 0,
    endIndent: endindent ?? 0,
    color: color ?? colorText1,
  );
}

setDropDownDecoratorProps(String hinttext,
    {Color? hintTextColor, Color? labelColor}) {
  return DropDownDecoratorProps(
      baseStyle: TextStyle(color: colorText1, fontWeight: fwt500),
      dropdownSearchDecoration: InputDecoration(
        contentPadding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
        hintStyle: TextStyle(
            color: hintTextColor ?? colorTextGreyDark, fontWeight: fwt400),
        labelStyle: TextStyle(
            color: labelColor ?? colorTextGreyDark, fontWeight: fwt500),
        hintText: hinttext,
        errorBorder: OutlineInputBorder(
            borderRadius: borderRadius13,
            borderSide: BorderSide(color: Color.fromARGB(255, 154, 161, 176))),
        disabledBorder: OutlineInputBorder(
            borderRadius: borderRadius13,
            borderSide: BorderSide(color: Color.fromARGB(255, 154, 161, 176))),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: borderRadius13,
            borderSide: BorderSide(color: Color.fromARGB(255, 154, 161, 176))),
        focusedBorder: OutlineInputBorder(
            borderRadius: borderRadius13,
            borderSide: BorderSide(color: Color.fromARGB(255, 154, 161, 176))),
        enabledBorder: OutlineInputBorder(
            borderRadius: borderRadius13,
            borderSide: BorderSide(color: Color.fromARGB(255, 154, 161, 176))),
        border: OutlineInputBorder(
            borderRadius: borderRadius13,
            borderSide: BorderSide(color: Color.fromARGB(255, 154, 161, 176))),
        suffixIconColor: colorText1,
      ));
}

Widget whiteButton(String text, Function fun,
    {double? bHeight, double? bWidth}) {
  return SizedBox(
    width: bWidth ?? Get.width * 0.9,
    height: bHeight ?? 60,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
          foregroundColor: whiteColor,
          backgroundColor: whiteColor,
          elevation: 1,
          side: BorderSide(color: Color(0xff024950), width: 1.5)),
      onPressed: () async {
        fun();
      },
      child: Center(
          child: Text(text,
              style:const TextStyle(
                  fontSize: 16,
                  color:  Color(0xff024950),
                  fontWeight: FontWeight.w500))),
    ),
  );
}

Widget blueButton(String text, Function fun,
    {double? bHeight,
    double? bWidth,
    Color? color,
    Color? textColor,
    double? fontSize}) {
  return SizedBox(
      width: bWidth ?? Get.width * 0.9,
      height: bHeight ?? 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
            foregroundColor: whiteColor,
            backgroundColor: color ?? colorText1,
            shape: RoundedRectangleBorder(borderRadius: borderRadius17)),
        onPressed: () async {
          fun();
        },
        child: Center(
            child: Text(text,
                style: TextStyle(
                    fontSize: fontSize ?? 17,
                    color: textColor ?? whiteColor,
                    fontWeight: FontWeight.w500))),
      ));
}
