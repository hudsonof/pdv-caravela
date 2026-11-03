import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/pos_models.dart';
import '../services/stone_pos_bridge.dart';
import '../widgets/support_button.dart';

class CommandScreen extends StatefulWidget {
  const CommandScreen({
    required this.session,
    required this.onLookup,
    required this.onLogout,
    super.key,
  });

  final PosSession session;
  final Future<void> Function(String code) onLookup;
  final VoidCallback onLogout;

  @override
  State<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends State<CommandScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Digite ou leia o número da comanda.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onLookup(code);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    FocusScope.of(context).unfocus();
    try {
      final value = await StonePosBridge.instance.scanBarcode();
      if (value == null || value.trim().isEmpty) return;
      _codeController.text = value.trim();
      await _lookup();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova operação'),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        child: Text(
                          widget.session.displayName.isEmpty
                              ? '?'
                              : widget.session.displayName[0].toUpperCase(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.session.displayName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              widget.session.profileName,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.verified_user_outlined, size: 20),
                    ],
                  ),
                  const SizedBox(height: 34),
                  Text(
                    'Identifique a comanda',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.session.isCashier
                        ? 'A conta do cliente será carregada para conferência.'
                        : 'Digite o número ou leia o código da comanda.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _codeController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _lookup(),
                    decoration: InputDecoration(
                      labelText: 'Número da comanda',
                      hintText: 'Ex.: 1234',
                      prefixIcon: const Icon(Icons.confirmation_number_outlined),
                      suffixIcon: IconButton(
                        onPressed: _busy ? null : _scan,
                        tooltip: 'Ler QR Code ou código de barras',
                        icon: const Icon(Icons.qr_code_scanner, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Ler QR Code ou código de barras'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _CommandError(message: _error!),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _busy ? null : _lookup,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continuar'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Terminal ' + AppConfig.terminalId,
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
}

class _CommandError extends StatelessWidget {
  const _CommandError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message),
      );
}
