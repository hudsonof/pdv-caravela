import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/pos_models.dart';
import '../services/stone_pos_bridge.dart';
import '../widgets/support_button.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({
    required this.session,
    required this.bill,
    required this.onRefresh,
    required this.onPreparePayment,
    required this.onPaymentReturn,
    required this.onNewCommand,
    required this.onLogout,
    super.key,
  });

  final PosSession session;
  final PosBill bill;
  final Future<PosBill> Function() onRefresh;
  final Future<String> Function(String idempotencyKey) onPreparePayment;
  final Future<PosBill> Function(StoneReturn? paymentReturn) onPaymentReturn;
  final VoidCallback onNewCommand;
  final VoidCallback onLogout;

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  StreamSubscription<StoneReturn>? _subscription;
  bool _printing = false;
  bool _startingPayment = false;
  bool _awaitingPayment = false;
  bool _checkingPayment = false;
  bool _paid = false;
  String? _attemptIdempotencyKey;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _paid = widget.bill.isPaid;
    _subscription = StonePosBridge.instance.returns.listen(_handleStoneReturn);
  }

  @override
  void didUpdateWidget(covariant CashierScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bill.isPaid && !_paid) {
      setState(() => _paid = true);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  List<Map<String, String>> _printContent() {
    final rows = <Map<String, String>>[
      {'type': 'text', 'content': 'CONTA DO CLIENTE', 'align': 'center', 'size': 'big'},
      {'type': 'line', 'content': 'Comanda: ' + widget.bill.commandCode},
    ];
    final table = widget.bill.tableNumber;
    if (table != null && table.isNotEmpty) {
      rows.add({'type': 'line', 'content': 'Mesa: ' + table});
    }
    rows.add({'type': 'line', 'content': '--------------------------------'});
    for (final item in widget.bill.items) {
      rows.add({
        'type': 'line',
        'content': item.quantity.toString() +
            ' x ' +
            item.name +
            '  ' +
            formatCents(item.totalCents),
      });
    }
    rows.add({'type': 'line', 'content': '--------------------------------'});
    rows.add({
      'type': 'line',
      'content': 'Subtotal  ' + formatCents(widget.bill.subtotalCents),
    });
    if (widget.bill.discountCents != 0) {
      rows.add({
        'type': 'line',
        'content': 'Descontos  ' + formatCents(-widget.bill.discountCents),
      });
    }
    if (widget.bill.surchargeCents != 0) {
      rows.add({
        'type': 'line',
        'content': 'Taxas e acréscimos  ' +
            formatCents(widget.bill.surchargeCents),
      });
    }
    rows.add({'type': 'text', 'content': 'TOTAL  ' + formatCents(widget.bill.totalCents), 'align': 'right', 'size': 'big'});
    rows.add({'type': 'line', 'content': 'Conta para conferência; não é comprovante de pagamento.'});
    return rows;
  }

  Future<void> _print() async {
    setState(() {
      _printing = true;
      _message = null;
    });
    final resultFuture = StonePosBridge.instance.returns
        .firstWhere((result) => result.host == 'print')
        .timeout(const Duration(seconds: 90));
    try {
      await StonePosBridge.instance.printBill(_printContent());
      final result = await resultFuture;
      final status = (result.values['result'] ??
              result.values['status'] ??
              result.values['code'] ??
              '')
          .toUpperCase();
      if (status == 'SUCCESS' || status == '0') {
        _setMessage('Conta impressa.', isError: false);
      } else {
        _setMessage(
          status.isEmpty
              ? 'A impressão retornou sem um status reconhecido.'
              : 'A impressora retornou: ' + status,
          isError: true,
        );
      }
    } on TimeoutException {
      _setMessage('Não recebemos a confirmação da impressão. Verifique o terminal.');
    } catch (error) {
      _setMessage(error.toString());
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _pay() async {
    if (widget.bill.totalCents <= 0) {
      _setMessage('O total da conta precisa ser maior que zero.');
      return;
    }
    setState(() {
      _startingPayment = true;
      _message = null;
    });
    try {
      final key = _attemptIdempotencyKey ?? _newAttemptKey();
      _attemptIdempotencyKey = key;
      final orderId = await widget.onPreparePayment(key);
      await StonePosBridge.instance.launchPayment(
        amountCents: widget.bill.totalCents,
        orderId: orderId,
      );
      if (!mounted) return;
      setState(() {
        _awaitingPayment = true;
        _message = 'Finalize a transação no app Stone. A comanda fechará após a confirmação.';
      });
      Future<void>.delayed(const Duration(minutes: 2), () {
        if (!mounted || !_awaitingPayment || _checkingPayment) return;
        _reconcile(null);
      });
    } catch (error) {
      _setMessage(error.toString());
    } finally {
      if (mounted) setState(() => _startingPayment = false);
    }
  }

  String _newAttemptKey() {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return 'cashier-' +
        DateTime.now().microsecondsSinceEpoch.toString() +
        '-' +
        random;
  }

  Future<void> _handleStoneReturn(StoneReturn result) async {
    if (result.host == 'pay-response') {
      await _reconcile(result);
    } else if (result.host == 'print' && _printing) {
      // A espera da impressão consome o mesmo retorno.
    }
  }

  Future<void> _reconcile(StoneReturn? paymentReturn) async {
    if (_checkingPayment || !mounted) return;
    setState(() {
      _checkingPayment = true;
      _message = 'Conferindo o resultado com o sistema de gestão…';
      _messageIsError = false;
    });
    try {
      final updatedBill = await widget.onPaymentReturn(paymentReturn);
      final isPaid = updatedBill.isPaid;
      if (!mounted) return;
      setState(() {
        _paid = isPaid;
        _awaitingPayment = !isPaid && updatedBill.hasPendingPayment;
        if (!_awaitingPayment) _attemptIdempotencyKey = null;
        _message = isPaid
            ? 'Pagamento confirmado. A comanda foi fechada.'
            : updatedBill.hasPendingPayment
                ? 'O pagamento ainda está em processamento. Não inicie outra cobrança.'
            : paymentReturn == null
                ? 'Não foi possível confirmar o pagamento. Atualize a conta antes de tentar novamente.'
                : paymentReturn.code == '0'
                    ? 'O app Stone retornou sucesso, mas o sistema ainda não confirmou o fechamento. Atualize a conta.'
                    : 'Pagamento não confirmado. A comanda continua aberta.';
        _messageIsError = !isPaid;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Não foi possível reconciliar o pagamento: ' + error.toString();
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _checkingPayment = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _checkingPayment = true);
    try {
      final refreshed = await widget.onRefresh();
      if (!mounted) return;
      setState(() {
        _paid = refreshed.isPaid;
        _awaitingPayment = !refreshed.isPaid && refreshed.hasPendingPayment;
        if (!_awaitingPayment) _attemptIdempotencyKey = null;
        _message = refreshed.isPaid
            ? 'Comanda já consta como paga.'
            : refreshed.hasPendingPayment
                ? 'Pagamento ainda em processamento. Aguarde antes de iniciar outra cobrança.'
                : 'Conta atualizada.';
        _messageIsError = false;
      });
    } catch (error) {
      _setMessage(error.toString());
    } finally {
      if (mounted) setState(() => _checkingPayment = false);
    }
  }

  void _setMessage(String message, {bool isError = true}) {
    if (mounted) {
      setState(() {
        _message = message;
        _messageIsError = isError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caixa'),
        actions: [
          const SupportButton(),
          IconButton(
            onPressed: _checkingPayment ? null : _refresh,
            tooltip: 'Atualizar conta',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, _) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Comanda ' + bill.commandCode,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  if (bill.tableNumber != null &&
                                      bill.tableNumber!.isNotEmpty)
                                    Chip(
                                      avatar: const Icon(Icons.table_bar, size: 18),
                                      label: Text('Mesa ' + bill.tableNumber!),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                formatCents(bill.totalCents),
                                style: Theme.of(context)
                                    .textTheme
                                    .displaySmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              Text(
                                _paid ? 'Paga' : 'Total a pagar',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: bill.items.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('Esta comanda não possui itens.'),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              itemCount: bill.items.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = bill.items[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(item.name),
                                  subtitle: Text(
                                    item.quantity.toString() +
                                        ' × ' +
                                        formatCents(item.unitPriceCents),
                                  ),
                                  trailing: Text(
                                    formatCents(item.totalCents),
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _AmountRow(
                            label: 'Subtotal',
                            amount: bill.subtotalCents,
                          ),
                          if (bill.discountCents != 0)
                            _AmountRow(
                              label: 'Descontos',
                              amount: -bill.discountCents,
                            ),
                          if (bill.surchargeCents != 0)
                            _AmountRow(
                              label: 'Taxas e acréscimos',
                              amount: bill.surchargeCents,
                            ),
                          const Divider(),
                          if (_message != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _message!,
                                style: TextStyle(
                                  color: _messageIsError
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (_paid)
                            FilledButton.icon(
                              onPressed: widget.onNewCommand,
                              icon: const Icon(Icons.add),
                              label: const Text('Nova comanda'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                              ),
                            )
                          else
                            LayoutBuilder(
                              builder: (context, buttonConstraints) {
                                final stacked = buttonConstraints.maxWidth < 470;
                                final printButton = OutlinedButton.icon(
                                  onPressed: _printing ? null : _print,
                                  icon: _printing
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.print_outlined),
                                  label: Text(_printing ? 'Imprimindo…' : 'Imprimir conta'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(54),
                                  ),
                                );
                                final payButton = FilledButton.icon(
                                  onPressed: _startingPayment ||
                                          _checkingPayment ||
                                          _awaitingPayment
                                      ? null
                                      : _pay,
                                  icon: _startingPayment || _checkingPayment
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.payments_outlined),
                                  label: Text(
                                    _awaitingPayment
                                        ? 'Aguardando Stone…'
                                        : 'Fechar / pagar com Stone',
                                  ),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(54),
                                  ),
                                );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      printButton,
                                      const SizedBox(height: 8),
                                      payButton,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: printButton),
                                    const SizedBox(width: 10),
                                    Expanded(child: payButton),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(formatCents(amount)),
          ],
        ),
      );
}
