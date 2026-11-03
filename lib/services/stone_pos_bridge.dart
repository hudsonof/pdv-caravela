import 'dart:async';

import 'package:flutter/services.dart';

import '../models/pos_models.dart';

class StonePosBridge {
  StonePosBridge._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final StonePosBridge instance = StonePosBridge._();
  static const MethodChannel _channel =
      MethodChannel('br.com.novocaravela.pdv/stone_pos');

  final StreamController<StoneReturn> _returns =
      StreamController<StoneReturn>.broadcast();

  Stream<StoneReturn> get returns => _returns.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'stoneReturn' && call.arguments is Map) {
      _returns.add(
        StoneReturn.fromMap(
          Map<Object?, Object?>.from(call.arguments as Map),
        ),
      );
    }
  }

  Future<StoneReturn?> readPendingReturn() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'readPendingReturn',
      );
      return result == null ? null : StoneReturn.fromMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Não foi possível recuperar o retorno Stone.');
    }
  }

  Future<void> clearPendingReturn() async {
    try {
      await _channel.invokeMethod<void>('clearPendingReturn');
    } on MissingPluginException {
      // A integração nativa só existe no build Android.
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Não foi possível limpar o retorno Stone.');
    }
  }

  Future<void> savePaymentContext({
    required String orderId,
    required String commandCode,
    required int amountCents,
    required String method,
    required String idempotencyKey,
  }) async {
    await _channel.invokeMethod<void>('savePaymentContext', {
      'orderId': orderId,
      'commandCode': commandCode,
      'amountCents': amountCents,
      'method': method,
      'idempotencyKey': idempotencyKey,
    });
  }

  Future<Map<String, dynamic>?> readPaymentContext() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
        'readPaymentContext',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Não foi possível recuperar a cobrança pendente.');
    }
  }

  Future<void> clearPaymentContext() async {
    try {
      await _channel.invokeMethod<void>('clearPaymentContext');
    } on MissingPluginException {
      // A integração nativa só existe no build Android.
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Não foi possível limpar a cobrança pendente.');
    }
  }

  Future<String?> scanBarcode() async {
    try {
      return await _channel.invokeMethod<String>('scanBarcode');
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Não foi possível abrir o leitor.');
    } on MissingPluginException {
      throw Exception('Leitura pela câmera disponível apenas no terminal Android.');
    }
  }

  Future<void> launchPayment({
    required int amountCents,
    required String transactionType,
    String? orderId,
  }) async {
    try {
      await _channel.invokeMethod<void>('launchPayment', {
        'amountCents': amountCents,
        'transactionType': transactionType,
        'orderId': orderId,
      });
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Não foi possível abrir o pagamento Stone.');
    } on MissingPluginException {
      throw Exception('Pagamento Stone disponível apenas no terminal Android.');
    }
  }

  Future<void> printBill(List<Map<String, String>> printableContent) async {
    try {
      await _channel.invokeMethod<void>('printBill', {
        'printableContent': printableContent,
      });
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Não foi possível abrir a impressão Stone.');
    } on MissingPluginException {
      throw Exception('Impressão Stone disponível apenas no terminal Android.');
    }
  }

  Future<void> openManagement(String url) async {
    try {
      await _channel.invokeMethod<void>('openManagement', {'url': url});
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Não foi possível abrir a gestão.');
    } on MissingPluginException {
      throw Exception('A abertura do sistema de gestão está disponível no Android.');
    }
  }
}
