import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/api_client.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.api, this.onChanged});

  final ApiClient api;
  final Future<void> Function({bool announce})? onChanged;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> items = [];
  Timer? timer;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
    timer =
        Timer.periodic(const Duration(seconds: 8), (_) => load(silent: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    try {
      final loaded = await widget.api.notifications();
      if (!mounted) return;
      setState(() {
        items = loaded;
        loading = false;
      });
    } catch (_) {
      if (!mounted || silent) return;
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          TextButton(
            onPressed: () async {
              await widget.api.markNotificationsRead();
              await load();
              await widget.onChanged?.call(announce: false);
            },
            child: const Text('Đã đọc'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Chưa có thông báo'))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: line)),
                        tileColor: item['read'] == true
                            ? Colors.white
                            : const Color(0xFFEFFAF7),
                        title: Text('${item['title']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${item['message']}'),
                      );
                    },
                  ),
                ),
    );
  }
}
