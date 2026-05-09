import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../errors/api_exception.dart';
import '../storage/secure_token_storage.dart';
import '../utils/request_id.dart';

class ApiClient {
  final SecureTokenStorage tokenStorage;
  final http.Client _httpClient;

  Future<void> Function()? onUnauthorized;
  Future<AuthTokens?>? _refreshInFlight;

  ApiClient({required this.tokenStorage, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client() {
    debugPrint('API BASE URL: ${ApiConfig.baseUrl}');
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParameters,
    bool auth = true,
  }) {
    return request('GET', path, queryParameters: queryParameters, auth: auth);
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
    bool auth = true,
  }) {
    return request(
      'POST',
      path,
      body: body,
      queryParameters: queryParameters,
      auth: auth,
    );
  }

  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
    bool auth = true,
  }) {
    return request(
      'PATCH',
      path,
      body: body,
      queryParameters: queryParameters,
      auth: auth,
    );
  }

  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
    bool auth = true,
  }) {
    return request(
      'DELETE',
      path,
      body: body,
      queryParameters: queryParameters,
      auth: auth,
    );
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
    bool auth = true,
    bool retryOnUnauthorized = true,
  }) async {
    try {
      final response = await _send(
        method,
        path,
        body: body,
        queryParameters: queryParameters,
        auth: auth,
      );

      if (response.statusCode == 401 && auth && retryOnUnauthorized) {
        final refreshed = await _refreshTokens();
        if (refreshed != null) {
          final retryResponse = await _send(
            method,
            path,
            body: body,
            queryParameters: queryParameters,
            auth: auth,
          );

          return _decodeOrThrow(retryResponse);
        }

        await onUnauthorized?.call();
      }

      return _decodeOrThrow(response);
    } on SocketException {
      throw const ApiException(message: '네트워크 연결을 확인한 뒤 다시 시도해 주세요.');
    } on TimeoutException {
      throw const ApiException(message: '요청 시간이 초과됐어요. 다시 시도해 주세요.');
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
    bool auth = true,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}$path',
    ).replace(queryParameters: queryParameters);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Request-ID': newRequestId(),
    };

    if (auth) {
      final token = await tokenStorage.readAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final encodedBody = body == null ? null : jsonEncode(body);

    debugPrint('REQUEST: $method $uri');
    debugPrint('API FULL URI: $uri');
    if (method == 'POST' && path == '/api/v1/events') {
      debugPrint(
        'POST /api/v1/events REQUEST BODY: ${encodedBody ?? '<empty body>'}',
        wrapWidth: 1024,
      );
    }

    final response = await switch (method) {
      'GET' => _httpClient.get(uri, headers: headers),
      'POST' => _httpClient.post(uri, headers: headers, body: encodedBody),
      'PATCH' => _httpClient.patch(uri, headers: headers, body: encodedBody),
      'DELETE' => _httpClient.delete(uri, headers: headers, body: encodedBody),
      _ => throw ApiException(message: '지원하지 않는 요청 방식이에요.'),
    }.timeout(const Duration(seconds: 20));

    debugPrint('RESPONSE: ${response.statusCode} $method $uri');
    _logResponseBody(response);

    return response;
  }

  void _logResponseBody(http.Response response) {
    final body = response.statusCode == 422
        ? _fullBodyForLog(response.body)
        : _trimBodyForLog(response.body);

    debugPrint('RESPONSE BODY: $body', wrapWidth: 1024);
  }

  String _fullBodyForLog(String body) {
    if (body.isEmpty) return '<empty body>';
    return body;
  }

  String _trimBodyForLog(String body) {
    if (body.isEmpty) return '<empty body>';
    const maxLength = 1200;
    if (body.length <= maxLength) return body;
    return '${body.substring(0, maxLength)}... <truncated>';
  }

  dynamic _decodeOrThrow(http.Response response) {
    final decoded = _decodeJson(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
        return decoded['data'];
      }
      return decoded;
    }

    if (response.statusCode == 422) {
      _logFastApiValidationDetail(decoded);
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: _messageForStatus(response.statusCode, decoded),
      details: decoded,
    );
  }

  dynamic _decodeJson(String body) {
    if (body.trim().isEmpty) return null;

    try {
      return jsonDecode(body);
    } on FormatException {
      return body;
    }
  }

  String _messageForStatus(int statusCode, dynamic decoded) {
    final envelopeMessage = _extractEnvelopeMessage(decoded);
    if (envelopeMessage != null && envelopeMessage.isNotEmpty) {
      return envelopeMessage;
    }

    return switch (statusCode) {
      401 => '세션이 만료됐어요. 다시 로그인해 주세요.',
      403 => '이 작업을 진행할 권한이 없어요.',
      429 => '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.',
      >= 500 => '서버에서 문제가 발생했어요. 잠시 후 다시 시도해 주세요.',
      _ => '요청을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
    };
  }

  String? _extractEnvelopeMessage(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return null;

    final validationMessage =
        _firstValidationMessage(decoded['detail']) ??
        _firstValidationMessage(decoded['errors']);
    final displayValidationMessage = _displayMessage(validationMessage);
    if (displayValidationMessage != null) {
      return displayValidationMessage;
    }

    final detail = decoded['detail'];
    final detailMessage = _displayMessage(detail is String ? detail : null);
    if (detailMessage != null) return detailMessage;

    final error = decoded['error'];
    final errorMessage = _displayMessage(error is String ? error : null);
    if (errorMessage != null) return errorMessage;
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      final displayMessage = _displayMessage(
        message is String ? message : null,
      );
      if (displayMessage != null) return displayMessage;
    }

    final message = decoded['message'];
    final displayMessage = _displayMessage(message is String ? message : null);
    if (displayMessage != null) return displayMessage;

    return null;
  }

  String? _displayMessage(String? message) {
    final trimmed = message?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return RegExp(r'[가-힣]').hasMatch(trimmed) ? trimmed : null;
  }

  String? _firstValidationMessage(dynamic detail) {
    if (detail is! List || detail.isEmpty) return null;

    for (final item in detail) {
      if (item is Map<String, dynamic>) {
        final message = item['msg'];
        if (message is String && message.isNotEmpty) return message;
      }
    }

    return null;
  }

  void _logFastApiValidationDetail(dynamic decoded) {
    debugPrint('FASTAPI 422 VALIDATION DETAIL:');

    if (decoded is! Map<String, dynamic>) {
      debugPrint(
        'FASTAPI 422 detail: ${_jsonForLog(decoded)}',
        wrapWidth: 1024,
      );
      return;
    }

    final detail = decoded['detail'];
    if (detail is List) {
      _logValidationItems(detail);
      return;
    }

    debugPrint('FASTAPI 422 detail: ${_jsonForLog(detail)}', wrapWidth: 1024);

    final errors = decoded['errors'];
    if (errors is List) {
      _logValidationItems(errors);
      return;
    }

    debugPrint('FASTAPI 422 errors: ${_jsonForLog(errors)}', wrapWidth: 1024);
  }

  void _logValidationItems(List<dynamic> items) {
    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      if (item is Map<String, dynamic>) {
        debugPrint(
          'FASTAPI 422 detail[$index].loc: ${_jsonForLog(item['loc'])}',
          wrapWidth: 1024,
        );
        debugPrint(
          'FASTAPI 422 detail[$index].msg: ${_jsonForLog(item['msg'])}',
          wrapWidth: 1024,
        );
        debugPrint(
          'FASTAPI 422 detail[$index].input: '
          '${item.containsKey('input') ? _jsonForLog(item['input']) : '<missing>'}',
          wrapWidth: 1024,
        );
        continue;
      }

      debugPrint(
        'FASTAPI 422 detail[$index]: ${_jsonForLog(item)}',
        wrapWidth: 1024,
      );
    }
  }

  String _jsonForLog(Object? value) {
    if (value == null) return 'null';
    try {
      return jsonEncode(value);
    } on JsonUnsupportedObjectError {
      return value.toString();
    }
  }

  Future<AuthTokens?> _refreshTokens() {
    _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });

    return _refreshInFlight!;
  }

  Future<AuthTokens?> _performRefresh() async {
    final refreshToken = await tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      final response = await _send(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refresh_token': refreshToken},
        auth: false,
      );
      final decoded = _decodeOrThrow(response);
      final tokens = AuthTokens.fromJson(_asMap(decoded));
      await tokenStorage.saveTokens(tokens);
      return tokens;
    } on ApiException {
      await tokenStorage.clear();
      return null;
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiException(message: '요청 결과를 확인하지 못했어요.');
  }
}
