import 'dart:math';

import 'package:flutter/material.dart';

import '../models/pos_models.dart';
import '../widgets/support_button.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    required this.command,
    required this.bill,
    required this.products,
    required this.onSubmit,
    required this.onCheckout,
    required this.onLogout,
    super.key,
  });

  final PosCommand command;
  final PosBill bill;
  final List<PosProduct> products;
  final Future<void> Function(List<OrderLineRequest> items, String idempotencyKey)
      onSubmit;
  final VoidCallback onCheckout;
  final VoidCallback onLogout;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _searchController = TextEditingController();
  final Map<String, int> _quantities = {};
  String _category = 'Todos';
  bool _submitting = false;
  String? _pendingIdempotencyKey;
  bool _retryRequired = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _categories {
    final values = widget.products.map((item) => item.category).toSet().toList()
      ..sort();
    return ['Todos', ...values];
  }

  List<PosProduct> get _visibleProducts {
    final query = _searchController.text.trim().toLowerCase();
    return widget.products.where((product) {
      final matchesCategory =
          _category == 'Todos' || product.category == _category;
      final matchesQuery = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          (product.description?.toLowerCase().contains(query) ?? false);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  int get _itemCount => _quantities.values.fold(0, (sum, value) => sum + value);

  int get _cartTotalCents {
    var total = 0;
    for (final entry in _quantities.entries) {
      final product =
          widget.products.where((item) => item.id == entry.key).firstOrNull;
      if (product != null) total += product.priceCents * entry.value;
    }
    return total;
  }

  void _changeQuantity(PosProduct product, int delta) {
    if (_retryRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tente novamente o envio antes de alterar a seleção.'),
        ),
      );
      return;
    }
    setState(() {
      final updated = (_quantities[product.id] ?? 0) + delta;
      if (updated <= 0) {
        _quantities.remove(product.id);
      } else {
        _quantities[product.id] = updated;
      }
      // A changed payload is a new operation; an unchanged retry reuses its key.
      _pendingIdempotencyKey = null;
    });
  }

  String _newIdempotencyKey() {
    final random = Random.secure().nextInt(1 << 32);
    return 'pos-' +
        DateTime.now().microsecondsSinceEpoch.toString() +
        '-' +
        random.toRadixString(16);
  }

  Future<void> _sendCart(BuildContext sheetContext) async {
    final lines = _quantities.entries
        .where((entry) => entry.value > 0)
        .map(
          (entry) => OrderLineRequest(
            productId: entry.key,
            quantity: entry.value,
          ),
        )
        .toList();
    if (lines.isEmpty) return;
    final idempotencyKey = _pendingIdempotencyKey ??= _newIdempotencyKey();
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(lines, idempotencyKey);
      if (!mounted) return;
      setState(() {
        _quantities.clear();
        _pendingIdempotencyKey = null;
        _retryRequired = false;
      });
      Navigator.of(sheetContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Itens enviados para a comanda.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _retryRequired = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showCart() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final entries = _quantities.entries.toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                8,
                18,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Itens da comanda ' + widget.command.code,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(
                              child: Text('Nenhum produto selecionado.'),
                            )
                          : ListView.separated(
                              itemCount: entries.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final entry = entries[index];
                                final product = widget.products
                                    .where((item) => item.id == entry.key)
                                    .firstOrNull;
                                if (product == null) {
                                  return const SizedBox.shrink();
                                }
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(product.name),
                                  subtitle: Text(
                                    formatCents(product.priceCents) +
                                        ' cada · ' +
                                        formatCents(
                                          product.priceCents * entry.value,
                                        ),
                                  ),
                                  trailing: _QuantityControl(
                                    quantity: entry.value,
                                    onMinus: () {
                                      _changeQuantity(product, -1);
                                      setSheetState(() {});
                                    },
                                    onPlus: () {
                                      _changeQuantity(product, 1);
                                      setSheetState(() {});
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total estimado'),
                        Text(
                          formatCents(_cartTotalCents),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _submitting || _itemCount == 0
                          ? null
                          : () => _sendCart(sheetContext),
                      icon: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(
                        _submitting ? 'Enviando…' : 'Enviar para a comanda',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = _visibleProducts;
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Produtos',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Buscar produto',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        return ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) => setState(() => _category = category),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: products.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhum produto disponível nesta busca.'),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final columns = width >= 900
                            ? 4
                            : width >= 560
                                ? 3
                                : 2;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: products.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: width < 400 ? .68 : .78,
                          ),
                          itemBuilder: (context, index) {
                            final product = products[index];
                            return _ProductCard(
                              product: product,
                              quantity: _quantities[product.id] ?? 0,
                              onAdd: () => _changeQuantity(product, 1),
                              onRemove: () => _changeQuantity(product, -1),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.bill.totalCents > 0) ...[
              OutlinedButton.icon(
                onPressed: widget.bill.isPaid ? null : widget.onCheckout,
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(
                  widget.bill.isPaid
                      ? 'Comanda paga'
                      : 'Conta ' +
                          formatCents(widget.bill.remainingCents) +
                          ' · conferir / pagar',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _itemCount == 0 ? null : _showCart,
              icon: const Icon(Icons.shopping_basket_outlined),
              label: Text(
                _itemCount == 0
                    ? 'Adicionar produtos à comanda'
                    : 'Ver seleção (' +
                        _itemCount.toString() +
                        ') · ' +
                        formatCents(_cartTotalCents),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final PosProduct product;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final image = product.imageUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: image == null || image.isEmpty
                ? ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.local_cafe_outlined, size: 44),
                  )
                : Image.network(
                    image,
                    cacheWidth: 512,
                    cacheHeight: 512,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    formatCents(product.priceCents),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  quantity == 0
                      ? SizedBox(
                          height: 40,
                          child: FilledButton(
                            onPressed: onAdd,
                            child: const Text('Adicionar'),
                          ),
                        )
                      : _QuantityControl(
                          quantity: quantity,
                          onMinus: onRemove,
                          onPlus: onAdd,
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.quantity,
    required this.onMinus,
    required this.onPlus,
  });

  final int quantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton.filledTonal(
            onPressed: onMinus,
            tooltip: 'Remover um',
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 36,
            child: Text(
              quantity.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton.filledTonal(
            onPressed: onPlus,
            tooltip: 'Adicionar um',
            icon: const Icon(Icons.add),
          ),
        ],
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
