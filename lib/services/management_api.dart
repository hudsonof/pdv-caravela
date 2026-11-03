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

class ManagementApi {
  ManagementApi({String? baseUrl})
      : _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceFirst(
          RegExp(r'/+$'),
          '',
        ) {
    _client.connectionTimeout = const Duration(seconds: 10);
  }

  final String _baseUrl;
  final HttpClient _client = HttpClient();

  bool get isConfigured => _baseUrl.isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) {
    if (!isConfigured) {
      throw const ApiException(
        'Configure API_BASE_URL para conectar ao sistema de gestão.',
      );
    }
    final base = Uri.parse(_baseUrl);
    final fullPath = base.path + AppConfig.apiPrefix + path;
    return base.replace(
      path: fullPath.replaceAll(RegExp(r'//+'), '/'),
      queryParameters: query,
    );
  }

  Future<Object?> _request(
    String method,
    String path, {
    String? token,
    Object? body,
    String? idempotencyKey,
    Map<String, String>? query,
  }) async {
    try {
      final request = await _client.openUrl(method, _uri(path, query)).timeout(
            const Duration(seconds: 15),
          );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (idempotencyKey != null) {
        request.headers.set('Idempotency-Key', idempotencyKey);
      }

      final response = await request.close().timeout(const Duration(seconds: 20));
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
        final message = decoded is Map ? decoded['message']?.toString() : null;
        throw ApiException(
          message?.isNotEmpty == true
              ? message!
              : 'O servidor respondeu com erro (' +
                  response.statusCode.toString() +
                  ').',
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
    } on FormatException {
      throw const ApiException('O endereço da API está inválido.');
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const ApiException('Resposta inválida do sistema de gestão.');
  }

  Future<PosSession> login({
    required String username,
    required String password,
  }) async {
    final response = await _request(
      'POST',
      '/auth/login',
      body: {
        'username': username,
        'password': password,
        'terminalId': AppConfig.terminalId,
      },
    );
    final session = PosSession.fromJson(_asMap(response));
    if (session.accessToken.isEmpty || session.profileCode.isEmpty) {
      throw const ApiException(
        'A resposta de login não trouxe token e perfil do atendente.',
      );
    }
    return session;
  }

  Future<PosCommand> findCommand(String code, String token) async {
    final response = await _request(
      'GET',
      '/commands/' + Uri.encodeComponent(code),
      token: token,
    );
    return PosCommand.fromJson(_asMap(response));
  }

  Future<void> updateTable({
    required String commandId,
    required String tableNumber,
    required String token,
  }) async {
    await _request(
      'PATCH',
      '/commands/' +
          Uri.encodeComponent(commandId) +
          '/table',
      token: token,
      body: {'tableNumber': tableNumber},
    );
  }

  Future<List<PosProduct>> getCatalog({
    required String profileCode,
    required String token,
  }) async {
    final response = await _request(
      'GET',
      '/catalog',
      token: token,
      query: {'profileCode': profileCode},
    );
    final map = _asMap(response);
    final products = map['products'];
    if (products is! List) {
      throw const ApiException('O catálogo recebido está em formato inválido.');
    }
    return products
        .whereType<Map>()
        .map((value) => PosProduct.fromJson(Map<String, dynamic>.from(value)))
        .where((product) => product.available)
        .toList();
  }

  Future<void> submitItems({
    required String commandId,
    required List<OrderLineRequest> items,
    required String token,
    required String idempotencyKey,
  }) async {
    await _request(
      'POST',
      '/commands/' +
          Uri.encodeComponent(commandId) +
          '/items',
      token: token,
      idempotencyKey: idempotencyKey,
      body: {'items': items.map((item) => item.toJson()).toList()},
    );
  }

  Future<PosBill> getBill({
    required String commandId,
    required String token,
  }) async {
    final response = await _request(
      'GET',
      '/commands/' +
          Uri.encodeComponent(commandId) +
          '/bill',
      token: token,
    );
    return PosBill.fromJson(_asMap(response));
  }

  Future<String> createPaymentAttempt({
    required String commandId,
    required String token,
    required int amountCents,
    required String idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/commands/' +
          Uri.encodeComponent(commandId) +
          '/payments/attempts',
      token: token,
      idempotencyKey: idempotencyKey,
      body: {'amountCents': amountCents},
    );
    final orderId = _readMapValue(response, 'paymentOrderId');
    if (orderId == null || orderId.isEmpty) {
      throw const ApiException(
        'O sistema não retornou o identificador do pagamento.',
      );
    }
    if (!RegExp(r'^\d+$').hasMatch(orderId)) {
      throw const ApiException(
        'O identificador do pagamento precisa ser numérico para o app Stone.',
      );
    }
    return orderId;
  }

  String? _readMapValue(Object? value, String key) {
    if (value is Map) return value[key]?.toString();
    return null;
  }

  Future<PosBill> reconcileStonePayment({
    required String commandId,
    required String token,
    required StoneReturn paymentReturn,
  }) async {
    final values = paymentReturn.values;
    await _request(
      'POST',
      '/commands/' +
          Uri.encodeComponent(commandId) +
          '/payments/reconcile',
      token: token,
      idempotencyKey: 'stone-' +
          (values['itk'] ?? values['order_id'] ?? commandId),
      body: {
        'returnCode': paymentReturn.code,
        'orderId': values['order_id'],
        'amountCents': int.tryParse(values['amount'] ?? ''),
        'transactionKey': values['itk'],
        'authorizationCode': values['authorization_code'],
      },
    );
    return getBill(commandId: commandId, token: token);
  }

  void close() => _client.close(force: true);
}
