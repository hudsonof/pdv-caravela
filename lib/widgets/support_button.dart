import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';

class SupportButton extends StatelessWidget {
  const SupportButton({super.key});

  Future<void> _showSupport(BuildContext context) async {
    final contact = AppConfig.supportContact.trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fale Conosco'),
        content: contact.isEmpty
            ? const Text(
                'Solicite os dados de suporte ao administrador do sistema.',
              )
            : SelectableText(contact),
        actions: [
          if (contact.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: contact));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contato copiado.')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: () => _showSupport(context),
        tooltip: 'Fale Conosco',
        icon: const Icon(Icons.help_outline),
      );
}
