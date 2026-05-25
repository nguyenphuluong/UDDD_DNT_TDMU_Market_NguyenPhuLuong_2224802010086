import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/api_client.dart';
import '../services/native_notifier.dart';
import 'cart_screen.dart';
import 'chat_list_screen.dart';
import 'login_screen.dart';
import 'market_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'sell_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final api = ApiClient('http://10.72.9.4:3000');
  final seenNotificationIds = <String>{};
  Map<String, dynamic>? user;
  Timer? badgeTimer;
  int tab = 0;
  int unreadNotifications = 0;
  int unreadChats = 0;
  int cartCount = 0;
  bool seededNotifications = false;

  @override
  void dispose() {
    badgeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return LoginScreen(api: api, onLogin: _onLogin);
    }

    final screens = [
      MarketScreen(api: api, user: user!),
      SellScreen(api: api),
      ChatListScreen(api: api, onChanged: refreshBadges),
      CartScreen(api: api, onChanged: refreshBadges),
      ProfileScreen(
        api: api,
        user: user!,
        onUserChanged: (value) => setState(() => user = value),
        onLogout: _logout,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 52,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
          child: Image.asset(
            'assets/branding/tdmu_market_icon_512.png',
            fit: BoxFit.contain,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TDMU Marketplace',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text(_title(tab),
                style: const TextStyle(
                    fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          _HeaderAvatar(user: user!),
          _BadgeIconButton(
            count: unreadNotifications,
            tooltip: 'Thông báo',
            icon: Icons.notifications_none_rounded,
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationsScreen(
                    api: api,
                    onChanged: refreshBadges,
                  ),
                ),
              );
              refreshBadges();
            },
          ),
        ],
      ),
      body: screens[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) {
          setState(() => tab = index);
          refreshBadges();
        },
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: 'Chợ'),
          const NavigationDestination(
              icon: Icon(Icons.add_box_outlined),
              selectedIcon: Icon(Icons.add_box),
              label: 'Đăng'),
          NavigationDestination(
              icon: _BadgeIcon(
                  count: unreadChats,
                  child: const Icon(Icons.chat_bubble_outline)),
              selectedIcon: _BadgeIcon(
                  count: unreadChats, child: const Icon(Icons.chat_bubble)),
              label: 'Chat'),
          NavigationDestination(
              icon: _BadgeIcon(
                  count: cartCount,
                  child: const Icon(Icons.shopping_bag_outlined)),
              selectedIcon: _BadgeIcon(
                  count: cartCount, child: const Icon(Icons.shopping_bag)),
              label: 'Giỏ'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Tôi'),
        ],
      ),
    );
  }

  String _title(int index) =>
      ['Chợ sinh viên', 'Đăng bán', 'Tin nhắn', 'Giỏ hàng', 'Cá nhân'][index];

  void _onLogin(Map<String, dynamic> value) {
    setState(() => user = value);
    refreshBadges(announce: false);
    badgeTimer?.cancel();
    badgeTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => refreshBadges(announce: true),
    );
  }

  Future<void> refreshBadges({bool announce = false}) async {
    if (user == null || api.token == null) return;
    try {
      final results = await Future.wait([
        api.notificationSummary(),
        api.chats(),
        api.cart(),
      ]);
      final notificationData = Map<String, dynamic>.from(results[0] as Map);
      final notifications =
          List<Map<String, dynamic>>.from(notificationData['notifications']);
      final chats = List<Map<String, dynamic>>.from(results[1] as List);
      final cart = Map<String, dynamic>.from(results[2] as Map);

      final unread = notifications
          .where((item) => item['read'] != true)
          .map((item) => '${item['id']}')
          .toSet();
      final newItems = notifications
          .where((item) => !seenNotificationIds.contains('${item['id']}'))
          .toList();
      seenNotificationIds.addAll(notifications.map((item) => '${item['id']}'));

      if (announce && seededNotifications && newItems.isNotEmpty) {
        final latest = newItems.first;
        await NativeNotifier.show(
          title: '${latest['title'] ?? 'TDMU Market'}',
          body: '${latest['message'] ?? ''}',
        );
      }
      seededNotifications = true;

      if (!mounted) return;
      setState(() {
        unreadNotifications = unread.length;
        unreadChats = chats.fold<int>(
          0,
          (sum, chat) => sum + _asInt(chat['unreadCount']),
        );
        cartCount = List<Map<String, dynamic>>.from(cart['items'] ?? []).length;
      });
    } catch (_) {
      // Network polling is best-effort; visible screens still show their own errors.
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }

  void _logout() {
    badgeTimer?.cancel();
    setState(() {
      api.token = null;
      user = null;
      tab = 0;
      unreadNotifications = 0;
      unreadChats = 0;
      cartCount = 0;
      seededNotifications = false;
      seenNotificationIds.clear();
    });
  }
}

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final image = '${user['avatarImage'] ?? ''}';
    final provider = image.startsWith('data:image/')
        ? MemoryImage(_decodeDataImage(image)) as ImageProvider
        : image.startsWith('http')
            ? NetworkImage(image)
            : null;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: CircleAvatar(
        radius: 17,
        backgroundColor: danger,
        backgroundImage: provider,
        child: provider != null
            ? null
            : Text('${user['avatar'] ?? 'SV'}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Uint8List _decodeDataImage(String value) {
    final comma = value.indexOf(',');
    return base64Decode(comma == -1 ? value : value.substring(comma + 1));
  }
}

class _BadgeIconButton extends StatelessWidget {
  const _BadgeIconButton({
    required this.count,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final int count;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: _BadgeIcon(count: count, child: Icon(icon)),
      onPressed: onPressed,
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            right: -7,
            top: -7,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: danger,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
