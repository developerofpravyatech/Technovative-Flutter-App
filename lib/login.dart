import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:teknovative_solution/controller/login_controller.dart';
import 'package:teknovative_solution/resources/color.dart';
import 'package:teknovative_solution/resources/constants.dart';
import 'package:teknovative_solution/resources/extensions.dart';
import 'package:teknovative_solution/resources/theme.dart';
import 'package:teknovative_solution/shared/common/state_status.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'shared/common/image_constant.dart';

class LoginScreen extends GetView<LoginController> {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return SafeArea(
      maintainBottomViewPadding: true,
      child: SafeArea(
        child: Scaffold(
          //backgroundColor: colorBlueGray,
          body: SingleChildScrollView(
            physics: isKeyboardVisible
                ? const AlwaysScrollableScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: Stack(
              children: [
                Container(
                  height: Get.height,
                  decoration: BoxDecoration(
                      image: DecorationImage(
                        fit: BoxFit.cover,
                        image: AssetImage(
                          ImageConstant.loginImg,
                          // fit: BoxFit.cover,
                        ),
                      )),
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        SizedBox(height: 50.dynamicHeight()),
                        Container(
                          alignment: Alignment.center,
                          child: Text("Welcome",
                              style: GoogleFonts.davidLibre(
                                  textStyle: const TextStyle(
                                      fontSize: 39,
                                      fontWeight: FontWeight.w700))
                            // Themes.getTextStyle(context)
                            //     .copyWith(fontSize: 23)
                          ),
                        ),
                        SizedBox(height: 30.dynamicHeight()),
                        Column(
                          children: [
                            Container(
                              // elevation: 10,
                              // shadowColor: cardShadow,
                              //color: Colors.white,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                color: whiteColor,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color.fromARGB(122, 144, 145, 148),
                                    blurRadius: 5,
                                    offset: Offset(2, 3),
                                    spreadRadius: 1,
                                  )
                                ],
                              ),

                              child: Padding(
                                padding:
                                const EdgeInsets.fromLTRB(14, 20, 14, 40),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 15),
                                    // getTextField("Self hosted url :", Icons.web_asset,
                                    //     urlController),
                                    // const SizedBox(height: 15),
                                    // getTextField(
                                    //     "Enter database :", Icons.storage, dbController),
                                    Container(
                                      alignment: Alignment.center,
                                      child: Text("Login",
                                          style: GoogleFonts.davidLibre(
                                              textStyle: const TextStyle(
                                                  fontSize: 30,
                                                  fontWeight: FontWeight.w600))
                                        // Themes.getTextStyle(context)
                                        //     .copyWith(fontSize: 23)
                                      ),
                                    ),
                                    SizedBox(height: 25.dynamicHeight()),
                                    Row(children: [
                                      SizedBox(
                                        width: 110,
                                        height: 50,
                                        child: DropdownSearch<String>(
                                          selectedItem:
                                          controller.hostString.value,
                                          onChanged: (newValue) {
                                            controller.hostString.value =
                                            newValue!;
                                            print(
                                                "hostString : ${controller.hostString}");
                                          },
                                          autoValidateMode: AutovalidateMode
                                              .onUserInteraction,
                                          itemAsString: (item) =>
                                              item.toString(),
                                          dropdownButtonProps:
                                          const DropdownButtonProps(
                                              style: ButtonStyle(
                                                  minimumSize:
                                                  MaterialStatePropertyAll(
                                                      Size.zero),
                                                  tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .padded,
                                                  padding:
                                                  MaterialStatePropertyAll(
                                                      EdgeInsets.zero)),
                                              padding: EdgeInsets.zero),
                                          popupProps: const PopupProps.menu(
                                              fit: FlexFit.loose),
                                          dropdownDecoratorProps:
                                          setDropDownDecoratorProps(
                                              "SELECT CONNECTION"),
                                          items: controller.hostStringList.value
                                              .toSet()
                                              .toList(),
                                        ),
                                      ),
                                      SizedBox(width: 5.dynamicWidth()),
                                      Expanded(
                                          child: getTextField(
                                              hintText: "URL",
                                              controller:
                                              controller.urlController))
                                    ]),

                                    SizedBox(height: 30.dynamicHeight()),
                                    getTextField(
                                        hintText: "Username",
                                        controller: controller.userController,
                                        prefix: Icon(
                                          Icons.person,
                                          size: 20,
                                          color: colorText1,
                                        )),
                                    SizedBox(height: 30.dynamicHeight()),
                                    Obx(() => getTextField(
                                        hintText: "Password",
                                        controller: controller.passController,
                                        obscureText: controller.showPass.value,
                                        prefix: Icon(
                                          Icons.settings,
                                          color: colorText1,
                                        ),
                                        suffix: GestureDetector(
                                          onTap: () {
                                            controller.showPass.value =
                                            !controller.showPass.value;
                                          },
                                          child: Icon(
                                            controller.showPass.value
                                                ? Icons.visibility
                                                : Icons.visibility_off,
                                            color: colorText1,
                                          ),
                                        ))),
                                    SizedBox(height: 40.dynamicHeight()),
                                    Center(
                                      child: Obx(() {
                                        final isLoading = controller
                                                .stateStatus ==
                                            StateStatus.LOADING;
                                        return InkWell(
                                          onTap: isLoading
                                              ? null
                                              : () {
                                                  debugPrint("Auth res : ");
                                                  controller.loginApiCall();
                                                },
                                          child: Container(
                                            alignment: Alignment.center,
                                            height: 50.dynamicHeight(),
                                            width: MediaQuery.sizeOf(context)
                                                    .width *
                                                0.7,
                                            decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                gradient:
                                                    const LinearGradient(
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                  stops: [0.0, 0.5, 1.0],
                                                  colors: [
                                                    Color(0xffea8372),
                                                    Color(0xffaf819d),
                                                    Color(0xff6d7cbd),
                                                  ],
                                                )),
                                            child: isLoading
                                                ? const SizedBox(
                                                    height: 24,
                                                    width: 24,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2.5,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : Text(
                                                    "Login",
                                                    style: Themes.getTextStyle(
                                                            context)
                                                        .copyWith(
                                                            color: whiteColor,
                                                            fontSize: 20,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600),
                                                  ),
                                          ),
                                        );
                                      }),
                                    )
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: 20.dynamicHeight())
                          ],
                        ),

                        SizedBox(height: 20.dynamicHeight()),
                        Center(
                          child: Container(
                              padding: const EdgeInsets.fromLTRB(5, 15, 5, 15),
                              alignment: Alignment.center,
                              width: 290,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                color: whiteColor,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color.fromARGB(122, 144, 145, 148),
                                    blurRadius: 5,
                                    offset: Offset(2, 3),
                                    spreadRadius: 1,
                                  )
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      var whatsappUrl =
                                          "whatsapp://send?phone=+919429242201"
                                          "&text=${Uri.encodeComponent("Need help for app")}";
                                      try {
                                        launchUrl(Uri.parse(whatsappUrl));
                                      } catch (e) {
                                        //To handle error and display error message
                                        Get.showSnackbar(const GetSnackBar(
                                            message:
                                            "Unable to open whatsapp"));
                                      }
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      // padding: EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: whiteColor,
                                        boxShadow: [
                                          BoxShadow(
                                            color: colorCardShadow,
                                            blurRadius: 4,
                                            offset: const Offset(0, 0),
                                            spreadRadius: 2,
                                          )
                                        ],
                                      ),
                                      child: Image.asset(
                                        ImageConstant.whatsappImg,
                                        height: 38,
                                        width: 38,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                    CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        "Need help?",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: blackColor,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 3),
                                      IntrinsicHeight(
                                        child: Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment.end,
                                          crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              "Whatsapp",
                                              textAlign: TextAlign.center,
                                              style:
                                              TextStyle(color: colorText1),
                                            ),
                                            const SizedBox(width: 3),
                                            verticalDivider(
                                                endindent: 2, startindent: 2),
                                            const SizedBox(width: 3),
                                            Text(
                                              "Website",
                                              textAlign: TextAlign.center,
                                              style:
                                              TextStyle(color: colorText1),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () {
                                      var whatsappUrl =
                                          "http://www.teknovativesolution.com";
                                      try {
                                        launchUrl(Uri.parse(whatsappUrl));
                                      } catch (e) {
                                        //To handle error and display error message
                                        Get.showSnackbar(const GetSnackBar(
                                            message: "Unable to open web"));
                                      }
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: whiteColor,
                                        boxShadow: [
                                          BoxShadow(
                                            color: colorCardShadow,
                                            blurRadius: 4,
                                            offset: const Offset(0, 0),
                                            spreadRadius: 2,
                                          )
                                        ],
                                      ),
                                      child: Image.asset(
                                        "assets/shild.png",
                                        height: 25,
                                        width: 25,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ],
                              )),
                        ),
                        // Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        //   InkWell(
                        //       onTap: () {
                        //         var whatsappUrl =
                        //             "whatsapp://send?phone=+919429242201"
                        //             "&text=${Uri.encodeComponent("Need help for app")}";
                        //         try {
                        //           launchUrl(Uri.parse(whatsappUrl));
                        //         } catch (e) {
                        //           //To handle error and display error message
                        //           Get.showSnackbar(const GetSnackBar(
                        //               message: "Unable to open whatsapp"));
                        //         }
                        //       },
                        //       child: Container(
                        //           width: 40,
                        //           height: 40,
                        //           decoration: BoxDecoration(
                        //               color: const Color(0xff02466D),
                        //               borderRadius: BorderRadius.circular(100)),
                        //           padding: const EdgeInsets.all(7),
                        //           child: Image.asset("assets/whatsapp.png",
                        //               color: whiteBGColor))),
                        //   SizedBox(width: 12.dynamicWidth()),
                        //   InkWell(
                        //       onTap: () {
                        //         var whatsappUrl =
                        //             "http://www.teknovativesolution.com";
                        //         try {
                        //           launchUrl(Uri.parse(whatsappUrl));
                        //         } catch (e) {
                        //           //To handle error and display error message
                        //           Get.showSnackbar(const GetSnackBar(
                        //               message: "Unable to open web"));
                        //         }
                        //       },
                        //       child: Container(
                        //           width: 40,
                        //           height: 40,
                        //           decoration: BoxDecoration(
                        //               color: const Color(0xff02466D),
                        //               borderRadius: BorderRadius.circular(100)),
                        //           padding: const EdgeInsets.all(7),
                        //           child: Icon(Icons.language, color: whiteBGColor))),
                        // ])
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // getTextField(
  //   String hint,
  //   FocusNode? focusNod,
  //   TextEditingController con, {
  //   Function()? onEditComplete,
  //   Widget? suffix,
  //   bool? isPassWord,
  //   Widget? prefix,
  // }) {
  //   return TextFormField(
  //     obscureText: isPassWord ?? false,
  //     controller: con,
  //     cursorColor: primaryColor,
  //     focusNode: focusNod,
  //     textInputAction: TextInputAction.done,
  //     onEditingComplete: onEditComplete ?? () {},
  //     decoration: InputDecoration(
  //       // prefix: Icon(Icons.abc),
  //       prefixIcon: prefix,
  //       suffixIcon: suffix,
  //       hintText: hint,
  //       hintStyle: const TextStyle(fontSize: 16),
  //     ),
  //   );

  getTextField({
    ValueChanged<String>? onChanged,
    TextEditingController? controller,
    double? height,
    double? width,
    int? maxLength,
    TextInputType? keyBoardType,
    String? hintText,
    String? labelText,
    int maxLines = 1,
    bool obscureText = false,
    Widget? suffix,
    FormFieldValidator<String>? validation,
    bool? editable,
    void Function()? ontap,
    bool readonly = false,
    Widget? prefix,
    Icon? icon,
  }) =>
      TextFormField(
        readOnly: readonly,
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyBoardType,

        autovalidateMode: AutovalidateMode.onUserInteraction,
        maxLength: maxLength,
        // style: TextStyle(color: loginBox),
        maxLines: maxLines,
        onChanged: onChanged,
        enabled: editable,
        onTap: ontap,
        style: TextStyle(color: colorText1, fontWeight: fwt500),
        decoration: InputDecoration(
          counterText: "",
          //border: InputBorder.none,
          hintStyle: TextStyle(color: colorTextGreyDark, fontWeight: fwt400),
          labelStyle: TextStyle(color: colorTextGreyDark, fontWeight: fwt500),
          //filled: true,
          enabledBorder: OutlineInputBorder(
              borderRadius: borderRadius28,
              borderSide: const BorderSide(
                  color: Color.fromARGB(255, 154, 161, 176), width: 1.0)),
          focusedBorder: OutlineInputBorder(
              borderRadius: borderRadius28,
              borderSide: const BorderSide(
                  color: Color.fromARGB(255, 154, 161, 176), width: 1.0)),
          errorBorder: OutlineInputBorder(
              borderRadius: borderRadius28,
              borderSide: const BorderSide(
                  color: Color.fromARGB(255, 154, 161, 176), width: 1.0)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: borderRadius28,
              borderSide: const BorderSide(
                  color: Color.fromARGB(255, 154, 161, 176), width: 1.0)),

          hintText: hintText,
          labelText: labelText,
          suffixIcon: suffix,
          prefixIcon: prefix,
          contentPadding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
        ),
        validator: validation,
      );
}