import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/ui_helpers.dart';
import '../services/api_client.dart';
import '../widgets/product_tile.dart';
import 'chat_room_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen(
      {super.key,
      required this.api,
      required this.product,
      required this.related});

  final ApiClient api;
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> related;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết sản phẩm')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await api.addCart('${product['id']}');
                    if (context.mounted) {
                      showSnack(context, 'Đã thêm vào giỏ hàng');
                    }
                  },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Giỏ hàng'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final chat = await api.startChat('${product['id']}');
                    final chats = await api.chats();
                    final fullChat = chats.firstWhere(
                        (item) => item['id'] == chat['id'],
                        orElse: () => chat);
                    if (context.mounted) {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ChatRoomScreen(api: api, chat: fullChat)));
                    }
                  },
                  icon: const Icon(Icons.chat_bubble),
                  label: const Text('Chat'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Image.network('${product['image']}', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 16),
          Text('${product['title']}',
              style:
                  const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(currency(product['price']),
              style: const TextStyle(
                  color: danger, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text('${product['category']}')),
              Chip(label: Text('${product['condition']}')),
              Chip(label: Text('${product['location']}')),
            ],
          ),
          const SizedBox(height: 12),
          Text('${product['description']}',
              style: const TextStyle(fontSize: 15, height: 1.45)),
          const SizedBox(height: 22),
          const Text('Sản phẩm liên quan',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (related.isEmpty)
            const Text('Chưa có sản phẩm liên quan',
                style: TextStyle(color: muted)),
          ...related.map((item) => ProductTile(product: item, onTap: () {})),
        ],
      ),
    );
  }
}
