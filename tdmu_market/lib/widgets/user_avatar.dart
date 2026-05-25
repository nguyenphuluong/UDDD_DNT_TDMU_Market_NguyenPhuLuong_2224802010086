import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 22,
    this.backgroundColor = brand,
  });

  final Map<String, dynamic> user;
  final double radius;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final image = '${user['avatarImage'] ?? ''}';
    final provider = image.startsWith('data:image/')
        ? MemoryImage(_decodeDataImage(image)) as ImageProvider
        : image.startsWith('http')
            ? NetworkImage(image)
            : null;

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      backgroundImage: provider,
      child: provider == null
          ? Text(
              '${user['avatar'] ?? 'SV'}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }

  Uint8List _decodeDataImage(String value) {
    final comma = value.indexOf(',');
    return base64Decode(comma == -1 ? value : value.substring(comma + 1));
  }
}
