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
    required this.onRecordPayment,
    required this.onNewCommand,
    required this.onBack,
    required this.onLogout,
    super.key,
  });

  final PosSession session;
  final PosBill bill;
  final Future<PosBill> Function() onRefresh;
  final Future<PosBill> Function({
    required int amountCents,
    required String method,
    required String idempotencyKey,
  }) onRecordPayment;
  final VoidCallback onNewCommand;
  final VoidCallback onBack;
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
  bool _needsPaymentSync = false;
  String _method = 'DEBIT';
  String? _attemptIdempotencyKey;
  StoneReturn? _successfulStoneReturn;
  int? _amountAtLaunch;
  int? _successfulAmountCents;
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
    if (widget.bill.isPaid && !_paid) _paid = true;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  List<Map<String, String>> _printContent() {
    final rows = <Map<String, String>>[
      {
        'type': 'text',
        'content': 'CONTA DO CLIENTE',
        'align': 'center',
        'size': 'big',
      },
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
    if (widget.bill.paidCents > 0) {
      rows.add({
        'type': 'line',
        'content': 'Já pago  ' + formatCents(widget.bill.paidCents),
      });
    }
    rows.add({
      'type': 'text',
      'content': 'A PAGAR  ' + formatCents(widget.bill.remainingCents),
      'align': 'right',
      'size': 'big',
    });
    rows.add({
      'type': 'line',
      'content': 'Conta para conferência; não é comprovante de pagamento.',
    });
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
    if (widget.bill.remainingCents <= 0) {
      _setMessage('Não há saldo pendente nesta comanda.');
      return;
    }
    setState(() {
      _startingPayment = true;
      _message = null;
    });
    _attemptIdempotencyKey ??= _newAttemptKey();
    _amountAtLaunch = widget.bill.remainingCents;
    setState(() {
      _awaitingPayment = true;
      _message = 'Finalize no app Stone. O pagamento será registrado após o retorno de sucesso.';
      _messageIsError = false;
    });
    try {
      await StonePosBridge.instance.launchPayment(
        amountCents: widget.bill.remainingCents,
        transactionType: _method,
      );
    } catch (error) {
      _awaitingPayment = false;
      _attemptIdempotencyKey = null;
      _setMessage(error.toString());
    } finally {
      if (mounted) setState(() => _startingPayment = false);
    }
  }

  String _newAttemptKey() {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return 'payment-' +
        DateTime.now().microsecondsSinceEpoch.toString() +
        '-' +
        random;
  }

  Future<void> _handleStoneReturn(StoneReturn result) async {
    if (result.host != 'pay-response' || !_awaitingPayment) return;
    if (result.code != '0') {
      if (mounted) {
        setState(() {
          _awaitingPayment = false;
          _attemptIdempotencyKey = null;
          _successfulStoneReturn = null;
          _successfulAmountCents = null;
          _amountAtLaunch = null;
          _message = 'Pagamento não aprovado no app Stone. A comanda continua aberta.';
          _messageIsError = true;
        });
      }
      return;
    }
    _successfulStoneReturn = result;
    final returnedType = (result.values['type'] ?? '').toUpperCase();
    if (returnedType.contains('DEBIT') || returnedType.contains('DÉBIT')) {
      _method = 'DEBIT';
    } else if (returnedType.contains('CREDIT') ||
        returnedType.contains('CRÉDIT')) {
      _method = 'CREDIT';
    } else if (returnedType.contains('PIX') ||
        returnedType.contains('INSTANT_PAYMENT')) {
      _method = 'PIX';
    }
    _successfulAmountCents =
        int.tryParse(result.values['amount'] ?? '') ?? _amountAtLaunch;
    await _registerSuccessfulPayment();
  }

  Future<void> _registerSuccessfulPayment() async {
    final key = _attemptIdempotencyKey;
    if (key == null || _checkingPayment || !mounted) return;
    setState(() {
      _checkingPayment = true;
      _needsPaymentSync = false;
      _message = 'Registrando o pagamento no sistema de gestão…';
      _messageIsError = false;
    });
    try {
      final updatedBill = await widget.onRecordPayment(
        // Stone reports the authorized amount in cents; preserve it for retries.
        amountCents: _successfulAmountCents ??
            _amountAtLaunch ??
            widget.bill.remainingCents,
        method: _method,
        idempotencyKey: key,
      );
      if (!mounted) return;
      setState(() {
        _paid = updatedBill.isPaid;
        _awaitingPayment = false;
        _needsPaymentSync = false;
        _attemptIdempotencyKey = null;
        _successfulStoneReturn = null;
        _successfulAmountCents = null;
        _message = _paid
            ? 'Pagamento confirmado e comanda fechada.'
            : 'Pagamento registrado. Saldo restante: ' +
                formatCents(updatedBill.remainingCents) + '.',
        _messageIsError = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _needsPaymentSync = true;
          _awaitingPayment = true;
          _message = 'A Stone retornou sucesso, mas o registro na gestão falhou. Não faça outra cobrança; tente sincronizar novamente. ' +
              error.toString();
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _checkingPayment = false);
    }
  }

  Future<void> _refresh() async {
    if (_checkingPayment) return;
    setState(() => _checkingPayment = true);
    try {
      final refreshed = await widget.onRefresh();
      if (!mounted) return;
      setState(() {
        _paid = refreshed.isPaid;
        _message = _paid
            ? 'Comanda já consta como paga.'
            : 'Conta atualizada. Saldo: ' +
                formatCents(refreshed.remainingCents) + '.',
        _messageIsError = false;
        if (_paid) {
          _awaitingPayment = false;
          _needsPaymentSync = false;
          _attemptIdempotencyKey = null;
          _successfulStoneReturn = null;
          _successfulAmountCents = null;
        } else if (_successfulStoneReturn == null) {
          _awaitingPayment = false;
          _attemptIdempotencyKey = null;
        }
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
        title: const Text('Conta do cliente'),
        actions: [
          const SupportButton(),
          IconButton(
            onPressed: _awaitingPayment || _needsPaymentSync
                ? null
                : widget.onBack,
            tooltip: 'Voltar aos produtos',
            icon: const Icon(Icons.arrow_back),
          ),
          IconButton(
            onPressed: _checkingPayment || (_awaitingPayment && !_needsPaymentSync)
                ? null
                : _refresh,
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
        child: Center(
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
                          const SizedBox(height: 8),
                          Text(
                            widget.session.displayName + ' · ' +
                                widget.session.profileName,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            formatCents(bill.remainingCents),
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            _paid ? 'Paga' : 'Saldo a pagar',
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
                          separatorBuilder: (_, __) => const Divider(height: 1),
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
                      _AmountRow(label: 'Subtotal', amount: bill.subtotalCents),
                      if (bill.paidCents > 0)
                        _AmountRow(label: 'Já pago', amount: -bill.paidCents),
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
                      else ...[
                        if (_needsPaymentSync)
                          OutlinedButton.icon(
                            onPressed: _checkingPayment
                                ? null
                                : _registerSuccessfulPayment,
                            icon: const Icon(Icons.sync),
                            label: const Text('Sincronizar pagamento aprovado'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        if (_needsPaymentSync) const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _method,
                          decoration: const InputDecoration(
                            labelText: 'Forma de pagamento Stone',
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'DEBIT',
                              child: Text('Cartão de débito'),
                            ),
                            DropdownMenuItem(
                              value: 'CREDIT',
                              child: Text('Cartão de crédito'),
                            ),
                            DropdownMenuItem(
                              value: 'PIX',
                              child: Text('Pix'),
                            ),
                          ],
                          onChanged: _awaitingPayment || _checkingPayment
                              ? null
                              : (value) {
                                  if (value != null) setState(() => _method = value);
                                },
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 470;
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
                              label: Text(
                                _printing ? 'Imprimindo…' : 'Imprimir conta',
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                              ),
                            );
                            final payButton = FilledButton.icon(
                              onPressed: _startingPayment ||
                                      _checkingPayment ||
                                      _awaitingPayment ||
                                      bill.remainingCents <= 0
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
                                    : 'Pagar ' +
                                        formatCents(bill.remainingCents),
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
                    ],
                  ),
                ),
              ],
            ),
          ),
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
