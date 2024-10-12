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
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:square_in_app_payments/models.dart';

// Replace this with the server host you create, if you have your own server running
// e.g. https://server-host.com
String chargeServerHost = "http://192.168.2.14:8000/api";
// Uri chargeUrl = Uri.parse("$chargeServerHost/chargeForCookie");
Uri chargeUrl = Uri.parse("$chargeServerHost");

class ChargeException implements Exception {
  String errorMessage;
  ChargeException(this.errorMessage);
}

Future<void> chargeCard(CardDetails result) async {
  var body = jsonEncode({"nonce": result.nonce});
  http.Response response;
  try {
    response = await http.post(chargeUrl, body: body, headers: {
      "Accept": "application/json",
      "content-type": "application/json"
    });
  } on SocketException catch (ex) {
    throw ChargeException(ex.message);
  }

  var responseBody = json.decode(response.body);
  if (response.statusCode == 200) {
    return;
  } else {
    throw ChargeException(responseBody["errorMessage"]);
  }
}

Future<void> chargeCardAfterBuyerVerification(
    String nonce, String token) async {
  var body = jsonEncode({"nonce": nonce, "token": token});
  http.Response response;
  try {
    response = await http.post(chargeUrl, body: body, headers: {
      "Accept": "application/json",
      "content-type": "application/json"
    });
  } on SocketException catch (ex) {
    throw ChargeException(ex.message);
  }

  var responseBody = json.decode(response.body);
  if (response.statusCode == 200) {
    return;
  } else {
    throw ChargeException(responseBody["errorMessage"]);
  }
}

Future<String> signin(String username, String email, String password) async {
  var body = jsonEncode({"username": username, "email": email, "password": password});
  http.Response response;
  Uri signinUrl = Uri.parse("$chargeUrl/auth/signin");
  try {
    response = await http.post(signinUrl, body: body, headers: {
      "Accept": "application/json",
      "content-type": "application/json"
    });
  } on SocketException catch (ex) {
    throw ChargeException(ex.message);
  }

  var responseBody = json.decode(response.body);
  if (response.statusCode == 202) {
    return responseBody["authorized_account"]["token"];
  } else {
    throw ChargeException(responseBody["errorMessage"]);
  }
}

Future<void> bindCard({required String token ,required String nonce}) async {
  Uri chargeUrl = Uri.parse("$chargeServerHost/payments/bind_payment_method");
  var body = jsonEncode(
      {
        "card_nonce": nonce,
        "cardholder_name": "ZengLi",
        "billing_address": {
          "address_line_1": "1455 Market St",
          "address_line_2": "",
          "locality": "San Francisco",
          "administrative_district_level_1": "CA",
          "postal_code": "94103",
          "country": "US"
        }
      }
  );
  http.Response response;
  Uri bindCardUrl = Uri.parse("$chargeUrl");
  try {
    response = await http.post(bindCardUrl, body: body, headers: {
      "Accept": "application/json",
      "content-type": "application/json",
      "token": token
    });
    return;
  } on SocketException catch (ex) {
    throw ChargeException(ex.message);
  }

}