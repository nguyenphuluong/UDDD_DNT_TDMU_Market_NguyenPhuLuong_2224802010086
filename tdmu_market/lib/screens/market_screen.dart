import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ui_helpers.dart';
import '../services/api_client.dart';
import '../widgets/product_tile.dart';
import 'product_detail_screen.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key, required this.api, required this.user});

  final ApiClient api;
  final Map<String, dynamic> user;

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  List<Map<String, dynamic>> products = [];
  List<String> categories = [];
  String selectedCategory = 'all';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final loadedProducts =
          await widget.api.products(category: selectedCategory);
      final loadedCategories = await widget.api.categories();
      products = loadedProducts;
      categories = loadedCategories;
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        children: [
          const _MarketHero(),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: selectedCategory,
            decoration: const InputDecoration(labelText: 'Danh mục'),
            items: [
              const DropdownMenuItem(
                  value: 'all', child: Text('Tất cả danh mục')),
              ...categories.map(
                  (item) => DropdownMenuItem(value: item, child: Text(item))),
            ],
            onChanged: (value) {
              selectedCategory = value ?? 'all';
              load();
            },
          ),
          const SizedBox(height: 12),
          if (products.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: cardDecoration(),
              child: const Center(child: Text('Chưa có sản phẩm phù hợp')),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: products.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.58,
              ),
              itemBuilder: (context, index) {
                final product = products[index];
                return ProductTile(
                  product: product,
                  compact: true,
                  onTap: () => _openDetail(product),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> product) async {
    final full = await widget.api.product('${product['id']}');
    final related = products
        .where((item) =>
            item['category'] == product['category'] &&
            item['id'] != product['id'])
        .take(4)
        .toList();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
            api: widget.api, product: full, related: related),
      ),
    );
  }
}

class _MarketHero extends StatelessWidget {
  const _MarketHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
            colors: [Color(0xFF00A58F), Color(0xFF06433D)]),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chợ sinh viên TDMU',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text(
              'Tìm đồ học tập, công nghệ, đồng phục và trao đổi an toàn trong trường.',
              style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
