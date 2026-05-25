import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/api_client.dart';
import '../widgets/user_avatar.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, required this.api, this.onChanged});

  final ApiClient api;
  final Future<void> Function({bool announce})? onChanged;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> chats = [];
  Timer? timer;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
    timer =
        Timer.periodic(const Duration(seconds: 6), (_) => load(silent: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    try {
      final loaded = _visibleChats(await widget.api.chats());
      if (!mounted) return;
      setState(() {
        chats = loaded;
        loading = false;
      });
    } catch (_) {
      if (!mounted || silent) return;
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (chats.isEmpty) return const Center(child: Text('Chưa có tin nhắn'));
    return RefreshIndicator(
      onRefresh: load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: chats.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final chat = chats[index];
          final other = Map<String, dynamic>.from(chat['other'] ?? {});
          final last = Map<String, dynamic>.from(chat['lastMessage'] ?? {});
          final unreadCount = _asInt(chat['unreadCount']);
          final unread = unreadCount > 0;
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: line),
            ),
            tileColor: Colors.white,
            leading: UserAvatar(user: other, radius: 24),
            title: Text(
              '${other['name'] ?? 'Sinh viên'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${last['text'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: unread ? ink : muted,
                  fontWeight: unread ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
            ),
            trailing: unread
                ? _UnreadBadge(count: unreadCount)
                : const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(
                    api: widget.api,
                    chat: chat,
                    onChanged: widget.onChanged,
                  ),
                ),
              );
              await load(silent: true);
              await widget.onChanged?.call(announce: false);
            },
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _visibleChats(List<Map<String, dynamic>> chats) {
    final grouped = <String, Map<String, dynamic>>{};
    for (final chat in chats) {
      if (chat['lastMessage'] == null) continue;
      final other = Map<String, dynamic>.from(chat['other'] ?? {});
      final key =
          '${other['id'] ?? other['email'] ?? other['name'] ?? chat['id']}';
      final current = grouped[key];
      if (current == null) {
        grouped[key] = {...chat, 'unreadCount': _asInt(chat['unreadCount'])};
      } else {
        current['unreadCount'] =
            _asInt(current['unreadCount']) + _asInt(chat['unreadCount']);
      }
    }
    return grouped.values.toList();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: danger,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
