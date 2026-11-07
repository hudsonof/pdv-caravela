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
  bool _manualReviewRequired = false;
  String _method = 'DEBIT';
  String? _attemptIdempotencyKey;
  StoneReturn? _successfulStoneReturn;
  int? _amountAtLaunch;
  int? _successfulAmountCents;
  String? _pendingOtherOrderCode;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _paid = widget.bill.isPaid;
    _subscription = StonePosBridge.instance.returns.listen(_handleStoneReturn);
    unawaited(_loadPendingStoneReturn());
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
    if (_pendingOtherOrderCode != null ||
        _manualReviewRequired ||
        _awaitingPayment) return;
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
    try {
      await StonePosBridge.instance.savePaymentContext(
        orderId: widget.bill.commandId,
        commandCode: widget.bill.commandCode,
        amountCents: widget.bill.remainingCents,
        method: _method,
        idempotencyKey: _attemptIdempotencyKey!,
      );
      if (!mounted) {
        await StonePosBridge.instance.clearPaymentContext();
        return;
      }
      setState(() {
        _awaitingPayment = true;
        _message = 'Finalize no app Stone. O pagamento será registrado após o retorno de sucesso.';
        _messageIsError = false;
      });
      await StonePosBridge.instance.launchPayment(
        amountCents: widget.bill.remainingCents,
        transactionType: _method,
      );
    } catch (error) {
      _awaitingPayment = false;
      _attemptIdempotencyKey = null;
      try {
        await StonePosBridge.instance.clearPaymentContext();
        _setMessage(error.toString());
      } catch (cleanupError) {
        _manualReviewRequired = true;
        _setMessage(
          'Não foi possível iniciar o pagamento nem limpar o estado local. Confira a Stone antes de outra tentativa. ' +
              cleanupError.toString(),
        );
      }
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
    if (result.host == 'print' && _printing) {
      await StonePosBridge.instance.clearPendingReturn();
      return;
    }
    if (result.host != 'pay-response' ||
        !_awaitingPayment ||
        _attemptIdempotencyKey == null ||
        _pendingOtherOrderCode != null ||
        _checkingPayment) {
      return;
    }
    if (result.code == null || result.code!.isEmpty) {
      if (mounted) {
        setState(() {
          _manualReviewRequired = true;
          _message = 'O retorno da Stone veio sem um código de aprovação. Confira a transação na Stone e na gestão antes de continuar.';
          _messageIsError = true;
        });
      }
      return;
    }
    if (result.code != '0') {
      await StonePosBridge.instance.clearPendingReturn();
      await StonePosBridge.instance.clearPaymentContext();
      if (mounted) {
        setState(() {
          _awaitingPayment = false;
          _manualReviewRequired = false;
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
    final expectedAmount = _amountAtLaunch;
    if (_successfulAmountCents == null ||
        expectedAmount == null ||
        _successfulAmountCents != expectedAmount) {
      if (mounted) {
        setState(() {
          _manualReviewRequired = true;
          _message = 'O valor retornado pela Stone não confere com o valor enviado. Confira a transação na Stone e na gestão antes de sincronizar ou cobrar novamente.';
          _messageIsError = true;
        });
      }
      return;
    }
    await _registerSuccessfulPayment();
  }

  Future<void> _loadPendingStoneReturn() async {
    try {
      final bridge = StonePosBridge.instance;
      final context = await bridge.readPaymentContext();
      if (!mounted) return;
      if (context != null) {
        final contextOrderId = context['orderId']?.toString();
        if (widget.bill.isPaid && contextOrderId == widget.bill.commandId) {
          await bridge.clearPaymentContext();
          await bridge.clearPendingReturn();
          return;
        }
        if (contextOrderId != widget.bill.commandId) {
          final otherCode = context['commandCode']?.toString() ?? '';
          if (otherCode.isEmpty) {
            setState(() {
              _awaitingPayment = true;
              _manualReviewRequired = true;
              _message = 'Existe uma cobrança Stone sem identificação de comanda. Confira a Stone e a gestão antes de continuar.';
              _messageIsError = true;
            });
            return;
          }
          setState(() {
            _pendingOtherOrderCode = otherCode;
            _awaitingPayment = true;
            _message = 'Há um pagamento Stone pendente para a comanda ' +
                otherCode +
                '. Abra essa comanda para sincronizar antes de iniciar outra cobrança.';
            _messageIsError = true;
          });
          return;
        }
        final key = context['idempotencyKey']?.toString() ?? '';
        final amount = context['amountCents'];
        final restoredAmount = amount is num
            ? amount.toInt()
            : int.tryParse(amount?.toString() ?? '');
        final method = context['method']?.toString() ?? _method;
        if (key.isEmpty ||
            restoredAmount == null ||
            restoredAmount <= 0 ||
            !const {'DEBIT', 'CREDIT', 'PIX'}.contains(method)) {
          setState(() {
            _awaitingPayment = true;
            _manualReviewRequired = true;
            _message = 'Existe um contexto de pagamento incompleto. Confira o terminal Stone antes de cobrar novamente.';
            _messageIsError = true;
          });
          return;
        }
        setState(() {
          _attemptIdempotencyKey = key;
          _amountAtLaunch = restoredAmount;
          _method = method;
          _awaitingPayment = true;
          _message = 'Pagamento Stone pendente. Confira o terminal para confirmar o resultado.';
          _messageIsError = false;
        });
        final pending = await bridge.readPendingReturn();
        if (!mounted) return;
        if (pending?.host == 'pay-response') {
          await _handleStoneReturn(pending!);
        } else if (pending?.host == 'print') {
          await bridge.clearPendingReturn();
          if (mounted) {
            setState(() {
              _manualReviewRequired = true;
              _message = 'Não recebemos o retorno do pagamento. Confira a transação na Stone e na gestão antes de continuar.';
              _messageIsError = true;
            });
          }
        } else if (mounted) {
          setState(() {
            _manualReviewRequired = true;
            _message = 'Não recebemos o retorno do pagamento. Confira a transação na Stone e na gestão antes de continuar.';
            _messageIsError = true;
          });
        }
        return;
      }

      final pending = await bridge.readPendingReturn();
      if (!mounted) return;
      if (pending != null && pending.host == 'pay-response') {
        setState(() {
          _manualReviewRequired = true;
          _message = 'Recebemos um retorno Stone sem o vínculo local da comanda. Confira o pagamento na Stone e na gestão antes de continuar.';
          _messageIsError = true;
        });
      } else if (pending != null) {
        await bridge.clearPendingReturn();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _manualReviewRequired = true;
          _message = 'Não foi possível recuperar com segurança o estado do pagamento. Confira a Stone e a gestão antes de continuar. ' +
              error.toString();
          _messageIsError = true;
        });
      }
    }
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
      await StonePosBridge.instance.clearPendingReturn();
      await StonePosBridge.instance.clearPaymentContext();
      if (!mounted) return;
      setState(() {
        _paid = updatedBill.isPaid;
        _awaitingPayment = false;
        _needsPaymentSync = false;
        _manualReviewRequired = false;
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
      if (refreshed.isPaid) {
        await StonePosBridge.instance.clearPendingReturn();
        await StonePosBridge.instance.clearPaymentContext();
      }
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
          _manualReviewRequired = false;
          _attemptIdempotencyKey = null;
          _successfulStoneReturn = null;
          _successfulAmountCents = null;
        }
      });
    } catch (error) {
      _setMessage(error.toString());
    } finally {
      if (mounted) setState(() => _checkingPayment = false);
    }
  }

  Future<void> _reviewPendingReturn() async {
    final hasLocalAttempt = _attemptIdempotencyKey != null;
    final stoneApproved = _successfulStoneReturn?.code == '0';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Conferir pagamento Stone'),
        content: Text(
          stoneApproved
              ? 'A Stone retornou aprovação, mas o valor não confere. Atualize a comanda e confira o valor no relatório Stone. Não libere uma nova cobrança até resolver a diferença.'
              : hasLocalAttempt
              ? 'Confirme somente depois de verificar no app Stone e na gestão que esta tentativa não foi aprovada nem registrada. Se houve aprovação, não libere uma nova cobrança.'
              : 'Confira o valor e o horário no app Stone e na gestão. Depois de verificar que não há pagamento pendente, você pode liberar o terminal para uma nova operação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Voltar'),
          ),
          if (!stoneApproved)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Conferi; não houve aprovação'),
            ),
          if (stoneApproved)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Atualizar comanda'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      if (confirmed == false && stoneApproved && mounted) await _refresh();
      return;
    }
    try {
      await StonePosBridge.instance.clearPendingReturn();
      await StonePosBridge.instance.clearPaymentContext();
    } catch (error) {
      _setMessage('Não foi possível limpar o retorno pendente. ' + error.toString());
      return;
    }
    if (!mounted) return;
    setState(() {
      _awaitingPayment = false;
      _needsPaymentSync = false;
      _manualReviewRequired = false;
      _pendingOtherOrderCode = null;
      _attemptIdempotencyKey = null;
      _successfulStoneReturn = null;
      _successfulAmountCents = null;
      _amountAtLaunch = null;
      _message = 'Tentativa conferida. A comanda continua aberta.';
      _messageIsError = false;
    });
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
                      if (_pendingOtherOrderCode != null)
                        OutlinedButton.icon(
                          onPressed: widget.onNewCommand,
                          icon: const Icon(Icons.manage_search),
                          label: Text(
                            'Abrir comanda ' + _pendingOtherOrderCode!,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      if (_manualReviewRequired) ...[
                        OutlinedButton.icon(
                          onPressed: _checkingPayment ? null : _reviewPendingReturn,
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Conferir situação no Stone e na gestão'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
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
                          onChanged: _awaitingPayment ||
                                  _checkingPayment ||
                                  _manualReviewRequired ||
                                  _pendingOtherOrderCode != null
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
                              onPressed: _printing ||
                                      _awaitingPayment ||
                                      _manualReviewRequired ||
                                      _pendingOtherOrderCode != null
                                  ? null
                                  : _print,
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
                                      _manualReviewRequired ||
                                      _pendingOtherOrderCode != null ||
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
