import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';

class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.onTap,
    this.compact = false,
  });

  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(compact ? 18 : 20);
    return Card(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: line),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(compact ? 18 : 20)),
              child: AspectRatio(
                aspectRatio: compact ? 1 : 16 / 9,
                child: Image.network(
                  '${product['image']}',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFFEAF1F0)),
                ),
              ),
            ),
            if (compact) Expanded(child: _content()) else _content(),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return Padding(
      padding: EdgeInsets.all(compact ? 9 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${product['title']}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: compact ? 13 : 17, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: compact ? 4 : 5),
          Text(
            currency(product['price']),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: danger,
                fontSize: compact ? 14 : 18,
                fontWeight: FontWeight.w900),
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            '${product['category']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontSize: compact ? 12 : 14),
          ),
          if (!compact) ...[
            const SizedBox(height: 2),
            Text('${product['condition']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted)),
          ],
        ],
      ),
    );
  }
}
