import 'dart:async';

import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'models/pos_models.dart';
import 'screens/cashier_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/command_screen.dart';
import 'screens/login_screen.dart';
import 'services/management_api.dart';
import 'services/stone_pos_bridge.dart';
import 'widgets/support_button.dart';

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

enum _FlowPage { login, events, command, catalog, checkout, management }

class _PosFlow extends StatefulWidget {
  const _PosFlow();

  @override
  State<_PosFlow> createState() => _PosFlowState();
}

class _PosFlowState extends State<_PosFlow> {
  final ManagementApi _api = ManagementApi();
  _FlowPage _page = _FlowPage.login;
  PosSession? _session;
  PosEvent? _event;
  PosBootstrap? _bootstrap;
  PosCommand? _command;
  PosBill? _bill;
  List<PosEvent> _events = const [];
  List<PosProduct> _products = const [];
  bool _busy = false;
  String _busyMessage = 'Aguarde…';
  String? _pageError;

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<PosSession> _login(String email, String password) async {
    final session = await _api.login(email: email, password: password);
    if (!session.isPosUser && !session.isManager && !session.isAdmin) {
      await _api.signOut();
      throw const ApiException(
        'Este usuário não possui um perfil compatível com o aplicativo.',
      );
    }
    if (!mounted) return session;
    if (session.isManager || session.isAdmin) {
      setState(() {
        _session = session;
        _page = _FlowPage.management;
      });
      return session;
    }

    final events = await _api.getEvents();
    if (!mounted) return session;
    setState(() {
      _session = session;
      _events = events;
      _pageError = null;
      _page = _FlowPage.events;
    });
    return session;
  }

  Future<void> _refreshEvents() async {
    setState(() {
      _busy = true;
      _busyMessage = 'Buscando eventos com caixa aberto…';
      _pageError = null;
    });
    try {
      final events = await _api.getEvents();
      if (!mounted) return;
      setState(() => _events = events);
    } catch (error) {
      if (mounted) setState(() => _pageError = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectEvent(PosEvent event) async {
    setState(() {
      _busy = true;
      _busyMessage = 'Carregando evento, sessão e catálogo…';
      _pageError = null;
    });
    try {
      final bootstrap = await _api.getBootstrap(event.id);
      if (!mounted) return;
      setState(() {
        _event = event;
        _bootstrap = bootstrap;
        _products = bootstrap.products;
        _page = _FlowPage.command;
      });
    } catch (error) {
      if (mounted) setState(() => _pageError = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lookupCommand(
    String code, {
    String? tableId,
    String? waiterEmployeeId,
  }) async {
    final event = _event;
    final bootstrap = _bootstrap;
    if (event == null || bootstrap == null) {
      throw const ApiException('Selecione novamente o evento do pedido.');
    }
    setState(() {
      _busy = true;
      _busyMessage = 'Consultando a comanda…';
    });
    try {
      final currentOrders = await _api.getOrders(event.id);
      var order = _findOpenOrder(currentOrders, code);
      if (order == null) {
        try {
          order = await _api.openOrder(
            eventId: event.id,
            commandCode: code,
            idempotencyKey: _newIdempotencyKey('open'),
            tableId: tableId,
            waiterEmployeeId: waiterEmployeeId,
          );
        } on ApiException catch (error) {
          if (error.statusCode != 409) rethrow;
          final refreshed = await _api.getOrders(event.id);
          order = _findOpenOrder(refreshed, code);
          if (order == null) rethrow;
        }
      }
      if (order == null) {
        throw const ApiException('Não foi possível localizar a comanda aberta.');
      }
      final resolvedOrder = order;
      final bill = await _api.getBill(resolvedOrder.id);
      if (!mounted) return;
      setState(() {
        _command = resolvedOrder;
        _bill = bill;
        _page = _FlowPage.catalog;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PosCommand? _findOpenOrder(List<PosCommand> orders, String code) {
    final normalizedCode = code.trim().toLowerCase();
    for (final order in orders) {
      if (order.code.trim().toLowerCase() == normalizedCode &&
          order.status.toUpperCase() == 'OPEN') {
        return order;
      }
    }
    return null;
  }

  Future<void> _submitItems(
    List<OrderLineRequest> items,
    String idempotencyKey,
  ) async {
    final command = _command;
    if (command == null) {
      throw const ApiException('A comanda não está disponível.');
    }
    await _api.submitItems(
      orderId: command.id,
      items: items,
      idempotencyKey: idempotencyKey,
    );
    final bill = await _api.getBill(command.id);
    if (mounted) setState(() => _bill = bill);
  }

  Future<PosBill> _refreshBill() async {
    final command = _command;
    if (command == null) {
      throw const ApiException('A comanda não está disponível.');
    }
    final bill = await _api.getBill(command.id);
    if (mounted) setState(() => _bill = bill);
    return bill;
  }

  Future<PosBill> _recordPayment({
    required int amountCents,
    required String method,
    required String idempotencyKey,
  }) async {
    final command = _command;
    if (command == null) {
      throw const ApiException('A comanda não está disponível.');
    }
    await _api.recordPayment(
      orderId: command.id,
      amountCents: amountCents,
      method: method,
      idempotencyKey: idempotencyKey,
    );
    final bill = await _api.getBill(command.id);
    if (mounted) setState(() => _bill = bill);
    return bill;
  }

  String _newIdempotencyKey(String action) {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'pdv-$action-$now';
  }

  void _openCheckout() {
    if (_bill == null) return;
    setState(() => _page = _FlowPage.checkout);
  }

  void _backToCatalog() {
    setState(() => _page = _FlowPage.catalog);
  }

  void _newCommand() {
    setState(() {
      _command = null;
      _bill = null;
      _page = _FlowPage.command;
    });
  }

  void _logout() {
    setState(() {
      _busy = true;
      _busyMessage = 'Encerrando sessão…';
    });
    unawaited(_finishLogout());
  }

  Future<void> _finishLogout() async {
    try {
      await _api.signOut();
    } catch (_) {
      // O cookie jar também é limpo localmente quando a chamada falha.
    }
    if (!mounted) return;
    setState(() {
      _session = null;
      _event = null;
      _bootstrap = null;
      _command = null;
      _bill = null;
      _events = const [];
      _products = const [];
      _pageError = null;
      _page = _FlowPage.login;
      _busy = false;
    });
  }

  Future<void> _openManagement() async {
    try {
      await StonePosBridge.instance.openManagement(AppConfig.apiBaseUrl);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Widget _eventsPage() {
    final session = _session!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecione o evento'),
        actions: [
          const SupportButton(),
          IconButton(
            onPressed: _busy ? null : _refreshEvents,
            tooltip: 'Atualizar eventos',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _logout,
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(session.displayName),
                  subtitle: Text(session.profileName + ' · ' + session.email),
                ),
                if (_pageError != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _pageError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                Expanded(
                  child: _events.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Não há eventos abertos com caixa disponível para este usuário.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _events.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final event = _events[index];
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.event_available_outlined),
                                ),
                                title: Text(event.name),
                                subtitle: event.startsAt == null
                                    ? null
                                    : Text(
                                        MaterialLocalizations.of(context)
                                            .formatMediumDate(event.startsAt!),
                                      ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _busy ? null : () => _selectEvent(event),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _managementPage() {
    final session = _session!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acesso à gestão'),
        actions: [
          IconButton(
            onPressed: _logout,
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.admin_panel_settings_outlined, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    'Olá, ' + session.displayName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sessão autenticada como ' + session.profileName +
                        '. As rotas de operação do PDV são exclusivas dos perfis POS. Use o sistema de gestão para as funções administrativas disponíveis para sua conta.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _openManagement,
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('Abrir sistema de gestão'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'O navegador pode solicitar novo login. A sessão do app e a sessão do navegador são independentes.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _currentPage() {
    switch (_page) {
      case _FlowPage.login:
        return LoginScreen(onLogin: _login);
      case _FlowPage.events:
        return _eventsPage();
      case _FlowPage.command:
        return CommandScreen(
          session: _session!,
          bootstrap: _bootstrap!,
          onLookup: _lookupCommand,
          onLogout: _logout,
        );
      case _FlowPage.catalog:
        return CatalogScreen(
          command: _command!,
          bill: _bill!,
          products: _products,
          onSubmit: _submitItems,
          onCheckout: _openCheckout,
          onLogout: _logout,
        );
      case _FlowPage.checkout:
        return CashierScreen(
          key: ValueKey(_command?.id),
          session: _session!,
          bill: _bill!,
          onRefresh: _refreshBill,
          onRecordPayment: _recordPayment,
          onNewCommand: _newCommand,
          onBack: _backToCatalog,
          onLogout: _logout,
        );
      case _FlowPage.management:
        return _managementPage();
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
