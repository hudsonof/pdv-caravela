import 'dart:async';

import 'package:flutter/services.dart';

import '../models/pos_models.dart';

class StonePosBridge {
  StonePosBridge._() {
    _channel.setMethodCallHandler(_handleNativeCall);
    _consumePendingReturn();
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

  Future<void> _consumePendingReturn() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'consumePendingReturn',
      );
      if (result != null) _returns.add(StoneReturn.fromMap(result));
    } on MissingPluginException {
      // A integração nativa só existe no build Android.
    } on PlatformException {
      // As ações mostram o erro ao serem solicitadas.
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
