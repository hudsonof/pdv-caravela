import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import '../models/pos_models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class _CookieJar {
  final Map<String, Cookie> _cookies = {};

  void absorb(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      final expired = (cookie.maxAge != null && cookie.maxAge! <= 0) ||
          (cookie.expires != null &&
              cookie.expires!.isBefore(DateTime.now()));
      if (expired) {
        _cookies.remove(cookie.name);
      } else {
        _cookies[cookie.name] = cookie;
      }
    }
  }

  String? headerFor(Uri uri) {
    final now = DateTime.now();
    _cookies.removeWhere((_, cookie) =>
        (cookie.maxAge != null && cookie.maxAge! <= 0) ||
        (cookie.expires != null && cookie.expires!.isBefore(now)));
    final matching = _cookies.values.where((cookie) {
      if (cookie.secure && uri.scheme != 'https') return false;
      final path = cookie.path;
      return path == null || uri.path.startsWith(path);
    }).toList();
    if (matching.isEmpty) return null;
    return matching.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  void clear() => _cookies.clear();
}

class ManagementApi {
  ManagementApi({String? baseUrl})
      : _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceFirst(
          RegExp(r'/+$'),
          '',
        ) {
    _client.connectionTimeout = const Duration(seconds: 12);
  }

  final String _baseUrl;
  final HttpClient _client = HttpClient();
  final _CookieJar _cookieJar = _CookieJar();
  PosSession? _session;

  bool get isConfigured => _baseUrl.isNotEmpty;
  Uri _uri(String path, [Map<String, String>? query]) {
    if (!isConfigured) {
      throw const ApiException('Configure a URL da API do sistema de gestão.');
    }
    final base = Uri.parse(_baseUrl);
    return base.replace(path: path, queryParameters: query);
  }

  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? form,
    Map<String, String>? query,
    String? idempotencyKey,
    bool allowRedirect = false,
  }) async {
    final uri = _uri(path, query);
    try {
      final request = await _client.openUrl(method, uri).timeout(
            const Duration(seconds: 15),
          );
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final cookieHeader = _cookieJar.headerFor(uri);
      if (cookieHeader != null) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }
      if (form != null) {
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-www-form-urlencoded; charset=utf-8',
        );
        request.write(Uri(queryParameters: form).query);
      } else if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      if (idempotencyKey != null) {
        request.headers.set('Idempotency-Key', idempotencyKey);
      }

      final response = await request.close().timeout(const Duration(seconds: 20));
      _cookieJar.absorb(response);
      if (response.statusCode >= 300 &&
          response.statusCode < 400 &&
          allowRedirect) {
        await response.drain<void>();
        return null;
      }
      final responseText = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 20));
      Object? decoded;
      if (responseText.isNotEmpty) {
        try {
          decoded = jsonDecode(responseText);
        } on FormatException {
          decoded = null;
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? (decoded['error'] ?? decoded['message'])?.toString()
            : null;
        final fallback = response.statusCode == 401
            ? 'Sua sessão expirou. Entre novamente.'
            : response.statusCode == 403
                ? 'Este perfil não tem permissão para esta operação.'
                : 'O sistema de gestão respondeu com erro (${response.statusCode}).';
        throw ApiException(
          message?.isNotEmpty == true ? message! : fallback,
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'A conexão demorou demais. Verifique a rede e tente novamente.',
      );
    } on SocketException {
      throw const ApiException(
        'Não foi possível conectar ao sistema de gestão.',
      );
    } on HandshakeException {
      throw const ApiException(
        'Não foi possível validar a conexão segura com o sistema de gestão.',
      );
    } on FormatException {
      throw const ApiException('A resposta do sistema de gestão está inválida.');
    } on HttpException {
      throw const ApiException('Falha na comunicação com o sistema de gestão.');
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const ApiException('Resposta inválida do sistema de gestão.');
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) {
      throw const ApiException('A lista recebida do sistema está inválida.');
    }
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<PosSession> login({
    required String email,
    required String password,
  }) async {
    _cookieJar.clear();
    _session = null;
    final csrfResponse = await _request('GET', '/api/auth/csrf');
    final csrfToken = _asMap(csrfResponse)['csrfToken']?.toString();
    if (csrfToken == null || csrfToken.isEmpty) {
      throw const ApiException('O sistema não retornou o token CSRF de login.');
    }

    await _request(
      'POST',
      '/api/auth/callback/credentials',
      allowRedirect: true,
      form: {
        'csrfToken': csrfToken,
        'email': email.trim(),
        'password': password,
        'callbackUrl': _baseUrl,
      },
    );
    final session = await getSession();
    if (session == null) {
      _cookieJar.clear();
      throw const ApiException('E-mail ou senha inválidos. Confira seus dados.');
    }
    _session = session;
    return session;
  }

  Future<PosSession?> getSession() async {
    final response = await _request('GET', '/api/auth/session');
    if (response is! Map || response['user'] is! Map) return null;
    final session = PosSession.fromAuthJson(_asMap(response));
    if (session.userId.isEmpty || session.role.isEmpty) return null;
    _session = session;
    return session;
  }

  Future<void> signOut() async {
    try {
      final response = await _request('GET', '/api/auth/csrf');
      final csrfToken = response is Map ? response['csrfToken']?.toString() : null;
      if (csrfToken != null && csrfToken.isNotEmpty) {
        await _request(
          'POST',
          '/api/auth/signout',
          allowRedirect: true,
          form: {'csrfToken': csrfToken, 'callbackUrl': _baseUrl},
        );
      }
    } finally {
      _cookieJar.clear();
      _session = null;
    }
  }

  Future<List<PosEvent>> getEvents() async {
    final response = await _request('GET', '/api/v1/pos/events');
    return _asMapList(response).map(PosEvent.fromJson).toList();
  }

  Future<PosBootstrap> getBootstrap(String eventId) async {
    final response = await _request(
      'GET',
      '/api/v1/pos/bootstrap',
      query: {'eventId': eventId},
    );
    return PosBootstrap.fromJson(_asMap(response));
  }

  Future<List<PosCommand>> getOrders(String eventId) async {
    final response = await _request(
      'GET',
      '/api/v1/pos/orders',
      query: {'eventId': eventId},
    );
    return _asMapList(response).map(PosCommand.fromJson).toList();
  }

  Future<PosCommand> openOrder({
    required String eventId,
    required String commandCode,
    required String idempotencyKey,
    String? tableId,
    String? waiterEmployeeId,
  }) async {
    final response = await _request(
      'POST',
      '/api/v1/pos/orders',
      idempotencyKey: idempotencyKey,
      body: {
        'eventId': eventId,
        'commandCode': commandCode,
        if (tableId != null && tableId.isNotEmpty) 'tableId': tableId,
        if (waiterEmployeeId != null && waiterEmployeeId.isNotEmpty)
          'waiterEmployeeId': waiterEmployeeId,
      },
    );
    return PosCommand.fromJson(_asMap(response));
  }

  Future<PosCommand> getOrder(String orderId) async {
    final response = await _request(
      'GET',
      '/api/v1/pos/orders/' + Uri.encodeComponent(orderId),
    );
    return PosCommand.fromJson(_asMap(response));
  }

  Future<PosBill> getBill(String orderId) async {
    final response = await _request(
      'GET',
      '/api/v1/pos/orders/' + Uri.encodeComponent(orderId),
    );
    return PosBill.fromOrderJson(_asMap(response));
  }

  Future<void> submitItems({
    required String orderId,
    required List<OrderLineRequest> items,
    required String idempotencyKey,
  }) async {
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      await _request(
        'POST',
        '/api/v1/pos/orders/' +
            Uri.encodeComponent(orderId) +
            '/items',
        idempotencyKey: '$idempotencyKey-${index + 1}',
        body: item.toJson(),
      );
    }
  }

  Future<void> recordPayment({
    required String orderId,
    required int amountCents,
    required String method,
    required String idempotencyKey,
  }) async {
    await _request(
      'POST',
      '/api/v1/pos/orders/' +
          Uri.encodeComponent(orderId) +
          '/payments',
      idempotencyKey: idempotencyKey,
      body: {
        'amount': centsToDecimal(amountCents),
        'method': method,
      },
    );
  }

  Future<void> cancelOrder({
    required String orderId,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _request(
      'POST',
      '/api/v1/pos/orders/' +
          Uri.encodeComponent(orderId) +
          '/cancel',
      idempotencyKey: idempotencyKey,
      body: {'reason': reason},
    );
  }

  void close() {
    _client.close(force: true);
    _cookieJar.clear();
    _session = null;
  }
}
