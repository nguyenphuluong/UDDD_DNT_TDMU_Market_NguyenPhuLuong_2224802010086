import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'screens/root_screen.dart';

void main() => runApp(const TdmuMarketApp());

class TdmuMarketApp extends StatelessWidget {
  const TdmuMarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TDMU Marketplace',
      theme: buildAppTheme(),
      home: const RootScreen(),
    );
  }
}
