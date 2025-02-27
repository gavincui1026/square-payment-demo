/*
 Copyright 2018 Square Inc.
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/
import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:square_in_app_payments/google_pay_constants.dart'
    as google_pay_constants;
import 'package:square_in_app_payments/in_app_payments.dart';
import 'package:square_in_app_payments/models.dart';
import 'package:uuid/uuid.dart';

import '../colors.dart';
import '../config.dart';
import '../transaction_service.dart';
import 'cookie_button.dart';
import 'dialog_modal.dart';
// We use a custom modal bottom sheet to override the default height (and remove it).
import 'login.dart';
import 'modal_bottom_sheet.dart' as custom_modal_bottom_sheet;
import 'order_sheet.dart';

enum ApplePayStatus { success, fail, unknown }

class BuySheet extends StatefulWidget {
  final bool? applePayEnabled;
  final bool? googlePayEnabled;
  final String? squareLocationId;
  final String? applePayMerchantId;
  static final GlobalKey<ScaffoldState> scaffoldKey =
      GlobalKey<ScaffoldState>();

  BuySheet(
      {this.applePayEnabled,
      this.googlePayEnabled,
      this.applePayMerchantId,
      this.squareLocationId});

  @override
  BuySheetState createState() => BuySheetState();
}

class BuySheetState extends State<BuySheet> {
  ApplePayStatus _applePayStatus = ApplePayStatus.unknown;

  bool get _chargeServerHostReplaced => chargeServerHost != "REPLACE_ME";

  bool get _squareLocationSet => widget.squareLocationId != "REPLACE_ME";

  bool get _applePayMerchantIdSet => widget.applePayMerchantId != "REPLACE_ME";

  bool isLoggedIn = false;

  void _handleLoginChange(bool loginStatus) {
    setState(() {
      isLoggedIn = loginStatus;
    });
  }

  void _showOrderSheet() async {
    var selection =
        await custom_modal_bottom_sheet.showModalBottomSheet<PaymentType>(
            context: BuySheet.scaffoldKey.currentState!.context,
            builder: (context) => OrderSheet(
                  applePayEnabled: widget.applePayEnabled!,
                  googlePayEnabled: widget.googlePayEnabled!,
                ));

    switch (selection) {
      case PaymentType.giftcardPayment:
        // call _onStartGiftCardEntryFlow to start Gift Card Entry.
        await _onStartGiftCardEntryFlow();
        break;
      case PaymentType.cardPayment:
        // call _onStartCardEntryFlow to start Card Entry without buyer verification (SCA)
        await _onStartCardEntryFlow();
        // OR call _onStartCardEntryFlowWithBuyerVerification to start Card Entry with buyer verification (SCA)
        // NOTE this requires _squareLocationSet to be set
        // await _onStartCardEntryFlowWithBuyerVerification();
        break;
      case PaymentType.buyerVerification:
        await _onStartBuyerVerificationFlow();
        break;
      case PaymentType.googlePay:
        if (_squareLocationSet && widget.googlePayEnabled!) {
          _onStartGooglePay();
        } else {
          _showSquareLocationIdNotSet();
        }
        break;
      case PaymentType.applePay:
        if (_applePayMerchantIdSet && widget.applePayEnabled!) {
          _onStartApplePay();
        } else {
          _showapplePayMerchantIdNotSet();
        }
        break;
      case PaymentType.secureRemoteCommerce:
        await _onStartSecureRemoteCommerceFlow();
        break;
    }
  }

  void printCurlCommand(String nonce, String? verificationToken) {
    var hostUrl = 'https://connect.squareup.com';
    if (squareApplicationId.startsWith('sandbox')) {
      hostUrl = 'https://connect.squareupsandbox.com';
    }
    var uuid = Uuid().v4();

    if (verificationToken == null) {
      print('curl --request POST $hostUrl/v2/payments \\'
          '--header \"Content-Type: application/json\" \\'
          '--header \"Authorization: Bearer YOUR_ACCESS_TOKEN\" \\'
          '--header \"Accept: application/json\" \\'
          '--data \'{'
          '\"idempotency_key\": \"$uuid\",'
          '\"amount_money\": {'
          '\"amount\": $cookieAmount,'
          '\"currency\": \"USD\"},'
          '\"source_id\": \"$nonce\"'
          '}\'');
    } else {
      print('curl --request POST $hostUrl/v2/payments \\'
          '--header \"Content-Type: application/json\" \\'
          '--header \"Authorization: Bearer YOUR_ACCESS_TOKEN\" \\'
          '--header \"Accept: application/json\" \\'
          '--data \'{'
          '\"idempotency_key\": \"$uuid\",'
          '\"amount_money\": {'
          '\"amount\": $cookieAmount,'
          '\"currency\": \"USD\"},'
          '\"source_id\": \"$nonce\",'
          '\"verification_token\": \"$verificationToken\"'
          '}\'');
    }
  }

  void _showUrlNotSetAndPrintCurlCommand(String nonce,
      {String? verificationToken}) {
    String title;
    if (verificationToken != null) {
      title = "Nonce and verification token generated but not charged";
    } else {
      title = "Nonce generated but not charged";
    }
    showAlertDialog(
        context: BuySheet.scaffoldKey.currentContext!,
        title: title,
        description:
            "Check your console for a CURL command to charge the nonce, or replace CHARGE_SERVER_HOST with your server host.",
        status: true);
    printCurlCommand(nonce, verificationToken);
  }

  void _showSquareLocationIdNotSet() {
    showAlertDialog(
        context: BuySheet.scaffoldKey.currentContext!,
        title: "Missing Square Location ID",
        description:
            "To request a Google Pay nonce, replace squareLocationId in main.dart with a Square Location ID.",
        status: false);
  }

  void _showapplePayMerchantIdNotSet() {
    showAlertDialog(
        context: BuySheet.scaffoldKey.currentContext!,
        title: "Missing Apple Merchant ID",
        description:
            "To request an Apple Pay nonce, replace applePayMerchantId in main.dart with an Apple Merchant ID.",
        status: false);
  }

  void _onCardEntryComplete() {
    if (_chargeServerHostReplaced) {
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Congratulation,Your order was successful",
          description:
              "Go to your Square dashboard to see this order reflected in the sales tab.",
          status: true);
    }
  }

  void _onCardEntryCardNonceRequestSuccess(CardDetails result) async {
    if (!_chargeServerHostReplaced) {
      InAppPayments.completeCardEntry(
          onCardEntryComplete: _onCardEntryComplete);
      _showUrlNotSetAndPrintCurlCommand(result.nonce);
      return;
    }
    try {
      // await chargeCard(result);
      await bindCard(
        token: Global.authentic_token!,
        nonce: result.nonce,

      );
      InAppPayments.completeCardEntry(
          onCardEntryComplete: _onCardEntryComplete);
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ChargeException catch (ex) {
      InAppPayments.showCardNonceProcessingError(ex.errorMessage);
    }
  }

  Future<void> _onStartCardEntryFlow() async {
    await InAppPayments.startCardEntryFlow(
        onCardNonceRequestSuccess: _onCardEntryCardNonceRequestSuccess,
        onCardEntryCancel: _onCancelCardEntryFlow,
        collectPostalCode: true);
  }

  Future<void> _onStartGiftCardEntryFlow() async {
    await InAppPayments.startGiftCardEntryFlow(
        onCardNonceRequestSuccess: _onCardEntryCardNonceRequestSuccess,
        onCardEntryCancel: _onCancelCardEntryFlow);
  }

  Future<void> _onStartCardEntryFlowWithBuyerVerification() async {
    var money = Money((b) => b
      ..amount = 100
      ..currencyCode = 'USD');

    var contact = Contact((b) => b
      ..givenName = "John"
      ..familyName = "Doe"
      ..addressLines =
          BuiltList<String>(["London Eye", "Riverside Walk"]).toBuilder()
      ..city = "London"
      ..countryCode = "GB"
      ..email = "johndoe@example.com"
      ..phone = "8001234567"
      ..postalCode = "SE1 7");

    await InAppPayments.startCardEntryFlowWithBuyerVerification(
        onBuyerVerificationSuccess: _onBuyerVerificationSuccess,
        onBuyerVerificationFailure: _onBuyerVerificationFailure,
        onCardEntryCancel: _onCancelCardEntryFlow,
        buyerAction: "Charge",
        money: money,
        squareLocationId: squareLocationId,
        contact: contact,
        collectPostalCode: true);
  }

  Future<void> _onStartBuyerVerificationFlow() async {
    var money = Money((b) => b
      ..amount = 100
      ..currencyCode = 'USD');

    var contact = Contact((b) => b
      ..givenName = "John"
      ..familyName = "Doe"
      ..addressLines =
          BuiltList<String>(["London Eye", "Riverside Walk"]).toBuilder()
      ..city = "London"
      ..countryCode = "GB"
      ..email = "johndoe@example.com"
      ..phone = "8001234567"
      ..postalCode = "SE1 7");

    await InAppPayments.startBuyerVerificationFlow(
        onBuyerVerificationSuccess: _onBuyerVerificationSuccess,
        onBuyerVerificationFailure: _onBuyerVerificationFailure,
        buyerAction: "Charge",
        money: money,
        squareLocationId: squareLocationId,
        contact: contact,
        paymentSourceId: "REPLACE_WITH_PAYMENT_SOURCE_ID");
  }

  void _onCancelCardEntryFlow() {
    _showOrderSheet();
  }

  void _onStartGooglePay() async {
    try {
      await InAppPayments.requestGooglePayNonce(
          priceStatus: google_pay_constants.totalPriceStatusFinal,
          price: getCookieAmount(),
          currencyCode: 'USD',
          onGooglePayNonceRequestSuccess: _onGooglePayNonceRequestSuccess,
          onGooglePayNonceRequestFailure: _onGooglePayNonceRequestFailure,
          onGooglePayCanceled: onGooglePayEntryCanceled);
    } on PlatformException catch (ex) {
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Failed to start GooglePay",
          description: ex.toString(),
          status: false);
    }
  }

  void _onGooglePayNonceRequestSuccess(CardDetails result) async {
    if (!_chargeServerHostReplaced) {
      _showUrlNotSetAndPrintCurlCommand(result.nonce);
      return;
    }
    try {
      await chargeCard(result);
    } on ChargeException catch (ex) {
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Error processing GooglePay payment",
          description: ex.errorMessage,
          status: false);
    }
  }

  void _onGooglePayNonceRequestFailure(ErrorInfo errorInfo) {
    showAlertDialog(
        context: BuySheet.scaffoldKey.currentContext!,
        title: "Failed to request GooglePay nonce",
        description: errorInfo.toString(),
        status: false);
  }

  void onGooglePayEntryCanceled() {
    _showOrderSheet();
  }

  void _onStartApplePay() async {
    try {
      await InAppPayments.requestApplePayNonce(
          price: getCookieAmount(),
          summaryLabel: 'Cookie',
          countryCode: 'US',
          currencyCode: 'USD',
          paymentType: ApplePayPaymentType.finalPayment,
          onApplePayNonceRequestSuccess: _onApplePayNonceRequestSuccess,
          onApplePayNonceRequestFailure: _onApplePayNonceRequestFailure,
          onApplePayComplete: _onApplePayEntryComplete);
    } on PlatformException catch (ex) {
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Failed to start ApplePay",
          description: ex.toString(),
          status: false);
    }
  }

  void _onBuyerVerificationSuccess(BuyerVerificationDetails result) async {
    if (!_chargeServerHostReplaced) {
      _showUrlNotSetAndPrintCurlCommand(result.nonce,
          verificationToken: result.token);
      return;
    }

    try {
      await chargeCardAfterBuyerVerification(result.nonce, result.token);
    } on ChargeException catch (ex) {
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Error processing card payment",
          description: ex.errorMessage,
          status: false);
    }
  }

  void _onApplePayNonceRequestSuccess(CardDetails result) async {
    if (!_chargeServerHostReplaced) {
      await InAppPayments.completeApplePayAuthorization(isSuccess: false);
      _showUrlNotSetAndPrintCurlCommand(result.nonce);
      return;
    }
    try {
      await chargeCard(result);
      _applePayStatus = ApplePayStatus.success;
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Congratulation,Your order was successful",
          description:
              "Go to your Square dashbord to see this order reflected in the sales tab.",
          status: true);
      await InAppPayments.completeApplePayAuthorization(isSuccess: true);
    } on ChargeException catch (ex) {
      await InAppPayments.completeApplePayAuthorization(
          isSuccess: false, errorMessage: ex.errorMessage);
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!, init
          title: "Error processing ApplePay payment",
          description: ex.errorMessage,
          status: false);
      _applePayStatus = ApplePayStatus.fail;
    }
  }

  void _onApplePayNonceRequestFailure(ErrorInfo errorInfo) async {
    _applePayStatus = ApplePayStatus.fail;
    await InAppPayments.completeApplePayAuthorization(
        isSuccess: false, errorMessage: errorInfo.message);
    showAlertDialog(
        context: BuySheet.scaffoldKey.currentContext!,
        title: "Error request ApplePay nonce",
        description: errorInfo.toString(),
        status: false);
  }

  void _onApplePayEntryComplete() {
    if (_applePayStatus == ApplePayStatus.unknown) {
      // the apple pay is canceled
      _showOrderSheet();
    }
  }

  void _onBuyerVerificationFailure(ErrorInfo errorInfo) async {
    showAlertDialog(
        context: BuySheet.scaffoldKey.currentContext!,
        title: "Error verifying buyer",
        description: errorInfo.toString(),
        status: false);
  }

  Future<void> _onStartSecureRemoteCommerceFlow() async {
    await InAppPayments.startSecureRemoteCommerce(
        amount: 100,
        onMaterCardNonceRequestSuccess: _onMaterCardNonceRequestSuccess,
        onMasterCardNonceRequestFailure: _onMasterCardNonceRequestFailure);
  }

  void _onMaterCardNonceRequestSuccess(CardDetails result) async {
    if (!_chargeServerHostReplaced) {
      _showUrlNotSetAndPrintCurlCommand(result.nonce);
      return;
    }

    try {
      await chargeCard(result);

    } on ChargeException catch (ex) {
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Error processing payment",
          description: ex.errorMessage,
          status: false);
    }
  }

  void _onMasterCardNonceRequestFailure(ErrorInfo errorInfo) async {
    showAlertDialog(
        context: BuySheet.scaffoldKey.currentContext!,
        title: "Error processing payment",
        description: errorInfo.toString(),
        status: false);
  }


  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(canvasColor: Colors.transparent),
    home: Scaffold(
      backgroundColor: mainBackgroundColor, // 保持原有的背景颜色
      key: BuySheet.scaffoldKey,
      body: Builder(
        builder: (context) => Center(
          child: Stack(
            children: [
              // 原有的内容
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    child: Image(image: AssetImage("assets/iconCookie.png")),
                  ),
                  Container(
                    child: Text(
                      'Super Cookie',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                      ),
                    ),
                  ),
                  Container(
                    child: Text(
                      "Instantly gain special powers \nwhen ordering a super cookie",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(top: 32),
                    child: CookieButton(
                        text: "Buy", onPressed: _showOrderSheet),
                  ),
                ],
              ),
              // 如果未登录，显示登录表单
              if (Global.authentic_token == null ||
                  Global.authentic_token!.isEmpty)
              // 使用 Positioned.fill 来覆盖整个屏幕，然后在 Center 中显示 LoginForm
                Positioned.fill(
                  child: Container(
                    child: Center(
                      child: (Global.authentic_token == null || Global.authentic_token!.isEmpty)
                          ? LoginForm(
                        onLoginChange: _handleLoginChange,
                      ) // 当 token 为空时显示 LoginForm
                          :  SizedBox.shrink(), // 当 token 不为空时，可以替换为其他小部件或留空
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
