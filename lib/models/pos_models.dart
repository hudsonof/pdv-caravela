int _readInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _readString(Object? value, [String fallback = '']) =>
    value?.toString().trim() ?? fallback;

int _readMoneyCents(Object? value) {
  if (value == null) return 0;
  if (value is num && value is! int) {
    return (value * 100).round();
  }
  final raw = value.toString().trim().replaceAll(',', '.');
  if (raw.isEmpty) return 0;
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$').firstMatch(raw);
  if (match == null) return int.tryParse(raw) ?? 0;
  final sign = match.group(1) == '-' ? -1 : 1;
  final whole = int.tryParse(match.group(2) ?? '') ?? 0;
  final fraction = (match.group(3) ?? '').padRight(2, '0');
  final cents = int.tryParse(fraction.substring(0, 2)) ?? 0;
  return sign * (whole * 100 + cents);
}

class PosSession {
  const PosSession({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.role,
    required this.posCashRegisterId,
    this.expiresAt,
  });

  final String userId;
  final String displayName;
  final String email;
  final String role;
  final String? posCashRegisterId;
  final DateTime? expiresAt;

  bool get isPosUser => const {
        'POS_TICKETS',
        'POS_TABLES',
        'POS_BAR',
        'POS_WAITER',
      }.contains(role.toUpperCase());

  bool get isManager => role.toUpperCase() == 'MANAGER';
  bool get isAdmin => role.toUpperCase() == 'ADMIN';

  String get profileName {
    switch (role.toUpperCase()) {
      case 'POS_TICKETS':
        return 'Bilheteria';
      case 'POS_TABLES':
        return 'Mesas';
      case 'POS_BAR':
        return 'Bar';
      case 'POS_WAITER':
        return 'Garçom';
      case 'MANAGER':
        return 'Gerente';
      case 'ADMIN':
        return 'Administrador';
      default:
        return role;
    }
  }

  factory PosSession.fromAuthJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PosSession(
      userId: _readString(user['id']),
      displayName: _readString(user['name'], 'Usuário'),
      email: _readString(user['email']),
      role: _readString(user['role']).toUpperCase(),
      posCashRegisterId: user['posCashRegisterId'] == null
          ? null
          : _readString(user['posCashRegisterId']),
      expiresAt: DateTime.tryParse(_readString(json['expires'])),
    );
  }
}

class PosEvent {
  const PosEvent({required this.id, required this.name, this.startsAt});

  final String id;
  final String name;
  final DateTime? startsAt;

  factory PosEvent.fromJson(Map<String, dynamic> json) => PosEvent(
        id: _readString(json['id']),
        name: _readString(json['name']),
        startsAt: DateTime.tryParse(_readString(json['startsAt'])),
      );
}

class PosTable {
  const PosTable({required this.id, required this.name});

  final String id;
  final String name;

  factory PosTable.fromJson(Map<String, dynamic> json) => PosTable(
        id: _readString(json['id']),
        name: _readString(json['name']),
      );
}

class PosEmployee {
  const PosEmployee({required this.id, required this.name});

  final String id;
  final String name;

  factory PosEmployee.fromJson(Map<String, dynamic> json) => PosEmployee(
        id: _readString(json['id']),
        name: _readString(json['name']),
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

  factory PosProduct.fromJson(Map<String, dynamic> json) {
    final type = _readString(json['type'], 'Produtos');
    return PosProduct(
      id: _readString(json['id']),
      name: _readString(json['name']),
      priceCents: json.containsKey('priceCents')
          ? _readInt(json['priceCents'])
          : _readMoneyCents(json['price'] ?? json['basePrice']),
      category: _readString(json['categoryName'] ?? json['category'], type),
      imageUrl: json['imageUrl'] == null
          ? null
          : _readString(json['imageUrl']),
      description: json['description'] == null
          ? null
          : _readString(json['description']),
      available: json['available'] != false && json['active'] != false,
    );
  }
}

class PosBootstrap {
  const PosBootstrap({
    required this.event,
    required this.products,
    required this.tables,
    required this.waiters,
    required this.profile,
    required this.registerName,
  });

  final PosEvent event;
  final List<PosProduct> products;
  final List<PosTable> tables;
  final List<PosEmployee> waiters;
  final String profile;
  final String registerName;

  factory PosBootstrap.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final event = (json['event'] as Map?)?.cast<String, dynamic>() ?? const {};
    final register =
        (json['register'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PosBootstrap(
      event: PosEvent.fromJson(event),
      products: (json['products'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => PosProduct.fromJson(
                Map<String, dynamic>.from(value),
              ))
          .where((product) => product.available)
          .toList(),
      tables: (json['tables'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => PosTable.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
      waiters: (json['waiters'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => PosEmployee.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
      profile: _readString(user['profile']).toUpperCase(),
      registerName: _readString(register['name']),
    );
  }
}

class PosCommand {
  const PosCommand({
    required this.id,
    required this.code,
    required this.status,
    this.eventId = '',
    this.tableNumber,
  });

  final String id;
  final String code;
  final String status;
  final String eventId;
  final String? tableNumber;

  bool get isClosed =>
      status.toUpperCase() == 'PAID' || status.toUpperCase() == 'CANCELLED';

  factory PosCommand.fromJson(Map<String, dynamic> json) {
    final table = (json['table'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PosCommand(
      id: _readString(json['id']),
      code: _readString(json['commandCode'] ?? json['code']),
      status: _readString(json['status'], 'OPEN'),
      eventId: _readString(json['eventId']),
      tableNumber: json['tableNameSnapshot'] == null && table['name'] == null
          ? null
          : _readString(json['tableNameSnapshot'] ?? table['name']),
    );
  }
}

class BillLine {
  const BillLine({
    required this.name,
    required this.quantity,
    required this.unitPriceCents,
    required this.totalCents,
  });

  final num quantity;
  final String name;
  final int unitPriceCents;
  final int totalCents;

  factory BillLine.fromJson(Map<String, dynamic> json) => BillLine(
        name: _readString(json['productName'] ?? json['name']),
        quantity: json['quantity'] is num
            ? json['quantity'] as num
            : num.tryParse(_readString(json['quantity'])) ?? 1,
        unitPriceCents: json.containsKey('unitPriceCents')
            ? _readInt(json['unitPriceCents'])
            : _readMoneyCents(json['unitPrice']),
        totalCents: json.containsKey('totalCents')
            ? _readInt(json['totalCents'])
            : _readMoneyCents(json['lineTotal'] ?? json['total']),
      );
}

class PosBill {
  const PosBill({
    required this.commandId,
    required this.commandCode,
    required this.status,
    required this.items,
    required this.subtotalCents,
    required this.discountCents,
    required this.surchargeCents,
    required this.totalCents,
    required this.paidCents,
    this.tableNumber,
  });

  final String commandId;
  final String commandCode;
  final String status;
  final List<BillLine> items;
  final int subtotalCents;
  final int discountCents;
  final int surchargeCents;
  final int totalCents;
  final int paidCents;
  final String? tableNumber;

  int get remainingCents =>
      (totalCents - paidCents).clamp(0, totalCents).toInt();

  bool get isPaid =>
      status.toUpperCase() == 'PAID' ||
      (totalCents > 0 && paidCents >= totalCents);

  bool get hasPendingPayment => false;

  factory PosBill.fromOrderJson(Map<String, dynamic> json) {
    final command = PosCommand.fromJson(json);
    final items = (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => BillLine.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final payments = (json['payments'] as List? ?? const [])
        .whereType<Map>()
        .map((payment) => Map<String, dynamic>.from(payment))
        .toList();
    final total = json.containsKey('totalCents')
        ? _readInt(json['totalCents'])
        : _readMoneyCents(json['total']);
    final paid = payments.fold<int>(
      0,
      (sum, payment) => sum +
          (payment.containsKey('amountCents')
              ? _readInt(payment['amountCents'])
              : _readMoneyCents(payment['amount'])),
    );
    final subtotal = items.fold<int>(0, (sum, item) => sum + item.totalCents);
    return PosBill(
      commandId: command.id,
      commandCode: command.code,
      status: command.status,
      items: items,
      subtotalCents: subtotal,
      discountCents: 0,
      surchargeCents: 0,
      totalCents: total,
      paidCents: paid,
      tableNumber: command.tableNumber,
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

String centsToDecimal(int cents) {
  final absolute = cents.abs();
  final value = (absolute ~/ 100).toString() +
      '.' +
      (absolute % 100).toString().padLeft(2, '0');
  return cents < 0 ? '-$value' : value;
}
