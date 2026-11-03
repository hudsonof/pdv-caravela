import 'package:flutter/material.dart';

import '../models/pos_models.dart';
import '../widgets/support_button.dart';

class TableScreen extends StatefulWidget {
  const TableScreen({
    required this.command,
    required this.onContinue,
    required this.onLogout,
    super.key,
  });

  final PosCommand command;
  final Future<void> Function(String? tableNumber) onContinue;
  final VoidCallback onLogout;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  late final TextEditingController _tableController =
      TextEditingController(text: widget.command.tableNumber ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _tableController.dispose();
    super.dispose();
  }

  Future<void> _continue({required bool skip}) async {
    final table = skip ? null : _tableController.text.trim();
    if (!skip && table!.isEmpty) {
      setState(() => _error = 'Informe a mesa ou escolha “Pular”.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onContinue(table);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Comanda ' + widget.command.code),
        actions: [
          const SupportButton(),
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.table_restaurant_outlined, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    'Qual é a mesa?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Informar a mesa é opcional. Você pode seguir direto para os produtos.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _tableController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _continue(skip: false),
                    decoration: const InputDecoration(
                      labelText: 'Número da mesa (opcional)',
                      prefixIcon: Icon(Icons.table_bar_outlined),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _continue(skip: false),
                      child: _busy
                          ? const CircularProgressIndicator()
                          : const Text('Continuar'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _continue(skip: true),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('Pular'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
