int _readInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _readString(Object? value, [String fallback = '']) =>
    value?.toString().trim() ?? fallback;

class PosSession {
  const PosSession({
    required this.accessToken,
    required this.userId,
    required this.displayName,
    required this.profileCode,
    required this.profileName,
    required this.permissions,
  });

  final String accessToken;
  final String userId;
  final String displayName;
  final String profileCode;
  final String profileName;
  final Set<String> permissions;

  bool get isCashier {
    final normalized = profileCode.toLowerCase();
    return normalized == 'cashier' ||
        normalized == 'caixa' ||
        permissions.any(
          (permission) => permission.toLowerCase() == 'pos.cashier',
        );
  }

  factory PosSession.fromJson(Map<String, dynamic> json) {
    final user = Map<String, dynamic>.from(
      (json['user'] as Map?)?.cast<String, dynamic>() ?? json,
    );
    final rawProfile = user['profile'] ?? user['role'] ?? user['profileCode'];
    final profile = rawProfile is Map
        ? Map<String, dynamic>.from(rawProfile.cast<String, dynamic>())
        : <String, dynamic>{};
    final permissions = (user['permissions'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();

    return PosSession(
      accessToken: _readString(json['accessToken'] ?? json['token']),
      userId: _readString(user['id']),
      displayName: _readString(user['displayName'] ?? user['name'], 'Atendente'),
      profileCode: _readString(
        profile['code'] ?? user['profileCode'] ?? rawProfile,
      ),
      profileName: _readString(
        profile['name'] ?? user['profileName'] ?? rawProfile,
        'Atendimento',
      ),
      permissions: permissions,
    );
  }
}

class PosCommand {
  const PosCommand({
    required this.id,
    required this.code,
    required this.status,
    this.tableNumber,
  });

  final String id;
  final String code;
  final String status;
  final String? tableNumber;

  bool get isClosed {
    final value = status.toLowerCase();
    return value == 'paid' || value == 'closed' || value == 'cancelled';
  }

  factory PosCommand.fromJson(Map<String, dynamic> json) => PosCommand(
        id: _readString(json['id']),
        code: _readString(json['code'] ?? json['number']),
        status: _readString(json['status'], 'open'),
        tableNumber: json['tableNumber'] == null
            ? null
            : _readString(json['tableNumber']),
      );
}

class PosProduct {
  const PosProduct({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.category,
    this.imageUrl,
    this.description,
    this.available = true,
  });

  final String id;
  final String name;
  final int priceCents;
  final String category;
  final String? imageUrl;
  final String? description;
  final bool available;

  factory PosProduct.fromJson(Map<String, dynamic> json) => PosProduct(
        id: _readString(json['id']),
        name: _readString(json['name']),
        priceCents: _readInt(json['priceCents']),
        category: _readString(json['categoryName'] ?? json['category'], 'Outros'),
        imageUrl: json['imageUrl'] == null
            ? null
            : _readString(json['imageUrl']),
        description: json['description'] == null
            ? null
            : _readString(json['description']),
        available: json['available'] != false,
      );
}

class BillLine {
  const BillLine({
    required this.name,
    required this.quantity,
    required this.unitPriceCents,
    required this.totalCents,
  });

  final String name;
  final num quantity;
  final int unitPriceCents;
  final int totalCents;

  factory BillLine.fromJson(Map<String, dynamic> json) => BillLine(
        name: _readString(json['name'] ?? json['productName']),
        quantity: json['quantity'] is num
            ? json['quantity'] as num
            : num.tryParse(_readString(json['quantity'])) ?? 1,
        unitPriceCents: _readInt(json['unitPriceCents']),
        totalCents: _readInt(json['totalCents']),
      );
}

class PosBill {
  const PosBill({
    required this.commandId,
    required this.commandCode,
    required this.status,
    this.paymentStatus = '',
    required this.items,
    required this.subtotalCents,
    required this.discountCents,
    required this.surchargeCents,
    required this.totalCents,
    this.tableNumber,
    this.paymentOrderId,
  });

  final String commandId;
  final String commandCode;
  final String status;
  final String paymentStatus;
  final List<BillLine> items;
  final int subtotalCents;
  final int discountCents;
  final int surchargeCents;
  final int totalCents;
  final String? tableNumber;
  final String? paymentOrderId;

  bool get isPaid {
    final value = status.toLowerCase();
    final payment = paymentStatus.toLowerCase();
    return value == 'paid' ||
        value == 'closed' ||
        value == 'settled' ||
        payment == 'paid' ||
        payment == 'settled';
  }

  bool get hasPendingPayment {
    final payment = paymentStatus.toLowerCase();
    return payment == 'pending' ||
        payment == 'processing' ||
        payment == 'authorized';
  }

  factory PosBill.fromJson(Map<String, dynamic> json) {
    final command = (json['command'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PosBill(
      commandId: _readString(json['commandId'] ?? command['id']),
      commandCode: _readString(json['commandCode'] ?? command['code']),
      status: _readString(json['status'], 'open'),
      paymentStatus: _readString(json['paymentStatus']),
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => BillLine.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      subtotalCents: _readInt(json['subtotalCents']),
      discountCents: _readInt(json['discountCents']),
      surchargeCents: _readInt(json['surchargeCents']),
      totalCents: _readInt(json['totalCents']),
      tableNumber: json['tableNumber'] == null
          ? null
          : _readString(json['tableNumber']),
      paymentOrderId: json['paymentOrderId'] == null
          ? null
          : _readString(json['paymentOrderId']),
    );
  }
}

class OrderLineRequest {
  const OrderLineRequest({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  Map<String, Object> toJson() => {
        'productId': productId,
        'quantity': quantity,
      };
}

class StoneReturn {
  const StoneReturn({
    required this.host,
    required this.code,
    required this.values,
  });

  final String host;
  final String? code;
  final Map<String, String> values;

  factory StoneReturn.fromMap(Map<Object?, Object?> map) {
    final values = (map['values'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
    return StoneReturn(
      host: map['host']?.toString() ?? '',
      code: values['code'],
      values: values,
    );
  }
}

String formatCents(int cents) {
  final absolute = cents.abs();
  final integerPart = (absolute ~/ 100).toString();
  final groupedInteger = integerPart.replaceAllMapped(
    RegExp(r'(?<=\d)(?=(\d{3})+$)'),
    (_) => '.',
  );
  final decimalPart = (absolute % 100).toString().padLeft(2, '0');
  return 'R\$ ' + (cents < 0 ? '-' : '') + '$groupedInteger,$decimalPart';
}
