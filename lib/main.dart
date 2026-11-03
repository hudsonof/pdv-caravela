import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'models/pos_models.dart';
import 'screens/cashier_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/command_screen.dart';
import 'screens/login_screen.dart';
import 'screens/table_screen.dart';
import 'services/management_api.dart';
import 'services/stone_pos_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  StonePosBridge.instance;
  runApp(const CaravelaPdvApp());
}

class CaravelaPdvApp extends StatelessWidget {
  const CaravelaPdvApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF126B57);
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF7F8F7),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDDE4E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: seed, width: 2),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const _PosFlow(),
    );
  }
}

enum _FlowPage { login, command, table, catalog, cashier }

class _PosFlow extends StatefulWidget {
  const _PosFlow();

  @override
  State<_PosFlow> createState() => _PosFlowState();
}

class _PosFlowState extends State<_PosFlow> {
  final ManagementApi _api = ManagementApi();
  _FlowPage _page = _FlowPage.login;
  PosSession? _session;
  PosCommand? _command;
  PosBill? _bill;
  List<PosProduct> _products = const [];
  bool _busy = false;
  String _busyMessage = 'Aguarde…';

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<PosSession> _login(String username, String password) async {
    final session = await _api.login(username: username, password: password);
    if (!mounted) return session;
    setState(() {
      _session = session;
      _page = _FlowPage.command;
    });
    return session;
  }

  Future<void> _lookupCommand(String code) async {
    final session = _session;
    if (session == null) throw const ApiException('A sessão expirou. Entre novamente.');
    setState(() {
      _busy = true;
      _busyMessage = 'Consultando comanda…';
    });
    try {
      final command = await _api.findCommand(code, session.accessToken);
      if (command.id.isEmpty) {
        throw const ApiException('A comanda recebida não possui identificador.');
      }
      if (command.isClosed && !session.isCashier) {
        throw const ApiException('Esta comanda já está fechada.');
      }

      if (session.isCashier) {
        final bill = await _api.getBill(
          commandId: command.id,
          token: session.accessToken,
        );
        if (!mounted) return;
        setState(() {
          _command = command;
          _bill = bill;
          _page = _FlowPage.cashier;
        });
      } else {
        if (command.isClosed) {
          throw const ApiException('Esta comanda já está fechada.');
        }
        setState(() {
          _command = command;
          _page = _FlowPage.table;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueToCatalog(String? tableNumber) async {
    final session = _session;
    final command = _command;
    if (session == null || command == null) {
      throw const ApiException('A sessão da comanda não está disponível.');
    }
    setState(() {
      _busy = true;
      _busyMessage = 'Carregando produtos…';
    });
    try {
      if (tableNumber != null && tableNumber.isNotEmpty) {
        await _api.updateTable(
          commandId: command.id,
          tableNumber: tableNumber,
          token: session.accessToken,
        );
      }
      final products = await _api.getCatalog(
        profileCode: session.profileCode,
        token: session.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
        _page = _FlowPage.catalog;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitItems(
    List<OrderLineRequest> items,
    String idempotencyKey,
  ) async {
    final session = _session;
    final command = _command;
    if (session == null || command == null) {
      throw const ApiException('A sessão da comanda não está disponível.');
    }
    await _api.submitItems(
      commandId: command.id,
      items: items,
      token: session.accessToken,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<PosBill> _refreshBill() async {
    final session = _session;
    final command = _command;
    if (session == null || command == null) {
      throw const ApiException('A sessão da comanda não está disponível.');
    }
    final bill = await _api.getBill(
      commandId: command.id,
      token: session.accessToken,
    );
    if (mounted) setState(() => _bill = bill);
    return bill;
  }

  Future<String> _preparePayment(String idempotencyKey) async {
    final session = _session;
    final command = _command;
    final bill = _bill;
    if (session == null || command == null || bill == null) {
      throw const ApiException('A sessão da comanda não está disponível.');
    }
    return _api.createPaymentAttempt(
      commandId: command.id,
      token: session.accessToken,
      amountCents: bill.totalCents,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<PosBill> _reconcilePayment(StoneReturn? paymentReturn) async {
    final session = _session;
    final command = _command;
    if (session == null || command == null) {
      throw const ApiException('A sessão da comanda não está disponível.');
    }
    final bill = paymentReturn == null
        ? await _api.getBill(
            commandId: command.id,
            token: session.accessToken,
          )
        : await _api.reconcileStonePayment(
            commandId: command.id,
            token: session.accessToken,
            paymentReturn: paymentReturn,
          );
    if (mounted) setState(() => _bill = bill);
    return bill;
  }

  void _newCommand() {
    setState(() {
      _command = null;
      _bill = null;
      _products = const [];
      _page = _FlowPage.command;
    });
  }

  void _logout() {
    setState(() {
      _session = null;
      _command = null;
      _bill = null;
      _products = const [];
      _page = _FlowPage.login;
    });
  }

  Widget _currentPage() {
    switch (_page) {
      case _FlowPage.login:
        return LoginScreen(onLogin: _login);
      case _FlowPage.command:
        return CommandScreen(
          session: _session!,
          onLookup: _lookupCommand,
          onLogout: _logout,
        );
      case _FlowPage.table:
        return TableScreen(
          command: _command!,
          onContinue: _continueToCatalog,
          onLogout: _logout,
        );
      case _FlowPage.catalog:
        return CatalogScreen(
          command: _command!,
          products: _products,
          onSubmit: _submitItems,
          onLogout: _logout,
        );
      case _FlowPage.cashier:
        return CashierScreen(
          key: ValueKey(_command?.id),
          session: _session!,
          bill: _bill!,
          onRefresh: _refreshBill,
          onPreparePayment: _preparePayment,
          onPaymentReturn: _reconcilePayment,
          onNewCommand: _newCommand,
          onLogout: _logout,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _currentPage(),
        if (_busy)
          ColoredBox(
            color: Colors.black.withValues(alpha: .28),
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 14),
                      Text(_busyMessage),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
