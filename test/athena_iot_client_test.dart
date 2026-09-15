/*
* Orion - Athena IoT Client Test
* Copyright (C) 2025 Open Resin Alliance
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orion/backend_service/athena_iot/athena_iot_client.dart';

void main() {
  test('uvledOff GETs the special screens off endpoint', () async {
    final fake = _FakeHttpClient(
      (request) async => http.Response('Ok', 200),
    );
    final client = AthenaIotClient(
      'http://printer.local',
      clientFactory: () => fake,
    );

    final result = await client.uvledOff();

    expect(result, isTrue);
    expect(fake.lastRequest!.method, 'GET');
    expect(
      fake.lastRequest!.url.toString(),
      'http://printer.local/athena-iot/specialscreens/uvled_off',
    );
  });

  test('uvledOff returns false when the backend rejects the request',
      () async {
    final fake = _FakeHttpClient(
      (request) async => http.Response('{"error":"no such command"}', 400),
    );
    final client = AthenaIotClient(
      'http://printer.local',
      clientFactory: () => fake,
    );

    final result = await client.uvledOff();

    expect(result, isFalse);
  });
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;
  http.Request? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final response = await _handler(
      http.Request(request.method, request.url)..body = body,
    );
    lastRequest = request as http.Request;
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close() {}
}
