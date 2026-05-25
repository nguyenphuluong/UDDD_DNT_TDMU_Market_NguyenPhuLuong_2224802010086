import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/ui_helpers.dart';
import '../services/api_client.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key, required this.api, this.onChanged});

  final ApiClient api;
  final Future<void> Function({bool announce})? onChanged;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  Map<String, dynamic>? cart;
  String method = 'banking';
  Timer? timer;

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 8), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    cart = await widget.api.cart();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (cart == null) return const Center(child: CircularProgressIndicator());
    final items = List<Map<String, dynamic>>.from(cart!['items']);
    final total = cart!['total'];
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          _CartHeader(count: items.length, total: total),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const _EmptyCart()
          else ...[
            ...items.map(
              (item) => _CartItemCard(
                item: item,
                onRemove: () => removeItem(item),
              ),
            ),
            const SizedBox(height: 4),
            _CheckoutPanel(
              method: method,
              total: total,
              onMethodChanged: (value) =>
                  setState(() => method = value ?? 'banking'),
              onCheckout: () => checkout(items),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> removeItem(Map<String, dynamic> item) async {
    final product = Map<String, dynamic>.from(item['product'] ?? {});
    await widget.api.removeCart('${product['id']}');
    await load();
    await widget.onChanged?.call(announce: false);
  }

  Future<void> checkout(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    final order = await widget.api.checkout(method);
    await load();
    await widget.onChanged?.call(announce: false);
    if (mounted) {
      showSnack(context, 'Thanh toán thành công: ${order['id']}');
    }
  }
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({required this.count, required this.total});

  final int count;
  final dynamic total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF00897B), Color(0xFF005F56)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.shopping_bag, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Giỏ hàng',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$count sản phẩm',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          Text(
            currency(total),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({required this.item, required this.onRemove});

  final Map<String, dynamic> item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final product = Map<String, dynamic>.from(item['product'] ?? {});
    final quantity = item['quantity'] ?? 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: cardDecoration(radius: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 86,
              height: 86,
              child: Image.network(
                '${product['image'] ?? ''}',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFFEAF1F0),
                  child: Icon(Icons.image_not_supported_outlined, color: muted),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 86,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product['title'] ?? 'Sản phẩm'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF7F4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'x$quantity',
                          style: const TextStyle(
                            color: brand,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currency(product['price']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: danger,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Xóa',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, color: danger),
          ),
        ],
      ),
    );
  }
}

class _CheckoutPanel extends StatelessWidget {
  const _CheckoutPanel({
    required this.method,
    required this.total,
    required this.onMethodChanged,
    required this.onCheckout,
  });

  final String method;
  final dynamic total;
  final ValueChanged<String?> onMethodChanged;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(radius: 22),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'Thanh toán online'),
            items: const [
              DropdownMenuItem(
                value: 'banking',
                child: Text('Chuyển khoản ngân hàng'),
              ),
              DropdownMenuItem(value: 'momo', child: Text('Ví MoMo demo')),
              DropdownMenuItem(value: 'zalopay', child: Text('ZaloPay demo')),
            ],
            onChanged: onMethodChanged,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tổng thanh toán',
                  style: TextStyle(color: muted, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                currency(total),
                style: const TextStyle(
                  color: danger,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onCheckout,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: brand,
            ),
            icon: const Icon(Icons.lock_outline),
            label: const Text('Thanh toán'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 36),
      decoration: cardDecoration(radius: 22),
      child: const Column(
        children: [
          Icon(Icons.shopping_bag_outlined, color: muted, size: 46),
          SizedBox(height: 12),
          Text(
            'Giỏ hàng đang trống',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 4),
          Text(
            'Sản phẩm bạn thêm sẽ xuất hiện tại đây.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}
