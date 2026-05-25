import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/ui_helpers.dart';
import '../services/api_client.dart';
import '../widgets/stat_card.dart';
import '../widgets/user_avatar.dart';

enum _AdminTab { stats, products, users }

class StatInfo {
  const StatInfo(this.label, this.value, this.type);

  final String label;
  final String value;
  final String type;
}

class AdminPanel extends StatefulWidget {
  const AdminPanel({
    super.key,
    required this.api,
    required this.currentUser,
  });

  final ApiClient api;
  final Map<String, dynamic> currentUser;

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  _AdminTab tab = _AdminTab.stats;
  String productStatus = 'pending';
  Map<String, dynamic> stats = {};
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> users = [];
  bool loading = true;
  bool loadingProducts = false;
  bool loadingUsers = false;

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  Future<void> loadAll() async {
    setState(() => loading = true);
    try {
      final loadedStats = await widget.api.adminStats();
      final loadedProducts =
          await widget.api.adminProducts(status: productStatus);
      final loadedUsers = await widget.api.adminUsers();
      if (!mounted) return;
      setState(() {
        stats = loadedStats;
        products = loadedProducts;
        users = loadedUsers;
      });
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadProducts() async {
    setState(() => loadingProducts = true);
    try {
      final loaded = await widget.api.adminProducts(status: productStatus);
      if (mounted) setState(() => products = loaded);
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loadingProducts = false);
    }
  }

  Future<void> loadUsers() async {
    setState(() => loadingUsers = true);
    try {
      final loaded = await widget.api.adminUsers();
      if (mounted) setState(() => users = loaded);
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loadingUsers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 12),
        _tabs(),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : switch (tab) {
                  _AdminTab.stats => _statsSection(),
                  _AdminTab.products => _productsSection(),
                  _AdminTab.users => _usersSection(),
                },
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(radius: 20),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: brand,
            foregroundColor: Colors.white,
            child: Icon(Icons.admin_panel_settings_outlined),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quản trị hệ thống',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text('Duyệt bài, thống kê và quản lý tài khoản',
                    style:
                        TextStyle(color: muted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Tải lại',
            onPressed: loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Row(
        children: [
          _tabItem('Thống kê', Icons.bar_chart_rounded, _AdminTab.stats),
          _tabItem('Bài đăng', Icons.inventory_2_outlined, _AdminTab.products),
          _tabItem('Tài khoản', Icons.group_outlined, _AdminTab.users),
        ],
      ),
    );
  }

  Widget _tabItem(String label, IconData icon, _AdminTab value) {
    final selected = tab == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => tab = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? brand : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: selected ? Colors.white : muted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsSection() {
    final items = [
      StatInfo('Người dùng', '${stats['users'] ?? 0}', 'users'),
      StatInfo('Đang khóa', '${stats['blockedUsers'] ?? 0}', 'blockedUsers'),
      StatInfo('Sản phẩm', '${stats['products'] ?? 0}', 'products'),
      StatInfo('Chờ duyệt', '${stats['pending'] ?? 0}', 'pending'),
      StatInfo('Đã duyệt', '${stats['approved'] ?? 0}', 'approved'),
      StatInfo('Đã ẩn', '${stats['hidden'] ?? 0}', 'hidden'),
      StatInfo('Đơn hàng', '${stats['orders'] ?? 0}', 'orders'),
      StatInfo('Doanh thu', currency(stats['revenue'] ?? 0), 'revenue'),
      StatInfo('Chat', '${stats['chats'] ?? 0}', 'chats'),
      StatInfo('Đánh giá', '${stats['reviews'] ?? 0}', 'reviews'),
    ];

    return GridView.builder(
      key: const ValueKey('stats'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.22,
      ),
      itemBuilder: (_, index) {
        final item = items[index];
        return StatCard(
          label: item.label,
          value: item.value,
          onTap: () => openStatDetail(item),
        );
      },
    );
  }

  Future<void> openStatDetail(StatInfo info) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatDetailSheet(api: widget.api, info: info),
    );
  }

  Widget _productsSection() {
    return Container(
      key: const ValueKey('products'),
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Duyệt bài đăng',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              IconButton(
                onPressed: loadingProducts ? null : loadProducts,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _statusFilter('Chờ duyệt', 'pending'),
                _statusFilter('Tất cả', 'all'),
                _statusFilter('Đã duyệt', 'approved'),
                _statusFilter('Đã ẩn', 'hidden'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (loadingProducts) const Center(child: CircularProgressIndicator()),
          if (!loadingProducts && products.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Không có bài đăng trong mục này.',
                  style: TextStyle(color: muted)),
            ),
          ...products.map(_productCard),
        ],
      ),
    );
  }

  Widget _statusFilter(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: productStatus == value,
        onSelected: (_) async {
          setState(() => productStatus = value);
          await loadProducts();
        },
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> product) {
    final seller = Map<String, dynamic>.from(product['seller'] ?? {});
    final status = '${product['status'] ?? 'pending'}';
    final approveNext = status == 'approved' ? 'hidden' : 'approved';
    final approveText = status == 'approved' ? 'Ẩn bài' : 'Duyệt';
    final approveIcon =
        status == 'approved' ? Icons.visibility_off_outlined : Icons.check;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  '${product['image']}',
                  width: 82,
                  height: 82,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Color(0xFFEAF1F0),
                    child: SizedBox(width: 82, height: 82),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusChip(status),
                        const Spacer(),
                        Text(currency(product['price']),
                            style: const TextStyle(
                                color: danger, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text('${product['title']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text('${seller['name'] ?? 'Người bán'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => moderate(product, approveNext),
                  icon: Icon(approveIcon),
                  label: Text(approveText),
                  style: FilledButton.styleFrom(
                    backgroundColor: approveNext == 'approved'
                        ? brand
                        : const Color(0xFF5F6B70),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Xóa bài',
                onPressed: () => deleteProduct(product),
                icon: const Icon(Icons.delete_outline),
                style: IconButton.styleFrom(foregroundColor: danger),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _usersSection() {
    return Container(
      key: const ValueKey('users'),
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Quản lý tài khoản',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              IconButton(
                onPressed: loadingUsers ? null : loadUsers,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (loadingUsers) const Center(child: CircularProgressIndicator()),
          if (!loadingUsers && users.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Chưa có tài khoản nào.',
                  style: TextStyle(color: muted)),
            ),
          ...users.map(_userCard),
        ],
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> user) {
    final isAdmin = user['role'] == 'admin';
    final isCurrent = user['id'] == widget.currentUser['id'];
    final blocked = user['status'] == 'blocked';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(user: user, radius: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${user['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('${user['email']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
              ),
              isAdmin ? _smallChip('Admin', brand) : _accountChip(blocked),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bài đăng ${user['productCount'] ?? 0}  |  Chờ duyệt ${user['pendingCount'] ?? 0}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
              if (!isAdmin && !isCurrent) ...[
                TextButton.icon(
                  onPressed: () =>
                      updateUserStatus(user, blocked ? 'active' : 'blocked'),
                  icon: Icon(blocked
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline_rounded),
                  label: Text(blocked ? 'Mở' : 'Khóa'),
                ),
                IconButton(
                  tooltip: 'Xóa tài khoản',
                  onPressed: () => deleteUser(user),
                  icon: const Icon(Icons.delete_outline, color: danger),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = status == 'approved'
        ? brand
        : status == 'pending'
            ? const Color(0xFF9B6500)
            : danger;
    final text = status == 'approved'
        ? 'Đã duyệt'
        : status == 'pending'
            ? 'Chờ duyệt'
            : 'Đã ẩn';
    return _smallChip(text, color);
  }

  Widget _accountChip(bool blocked) {
    return _smallChip(
        blocked ? 'Đã khóa' : 'Hoạt động', blocked ? danger : brand);
  }

  Widget _smallChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Future<void> moderate(Map<String, dynamic> product, String status) async {
    await widget.api.moderateProduct('${product['id']}', status);
    await loadProducts();
    final freshStats = await widget.api.adminStats();
    if (mounted) {
      setState(() => stats = freshStats);
      showSnack(context, status == 'approved' ? 'Đã duyệt bài' : 'Đã ẩn bài');
    }
  }

  Future<void> deleteProduct(Map<String, dynamic> product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa bài đăng?'),
        content: Text('Xóa "${product['title']}" khỏi hệ thống?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.api.adminDeleteProduct('${product['id']}');
    await loadProducts();
    final freshStats = await widget.api.adminStats();
    if (mounted) {
      setState(() => stats = freshStats);
      showSnack(context, 'Đã xóa bài đăng');
    }
  }

  Future<void> updateUserStatus(
      Map<String, dynamic> user, String status) async {
    await widget.api.updateUserStatus('${user['id']}', status);
    await loadUsers();
    final freshStats = await widget.api.adminStats();
    if (mounted) {
      setState(() => stats = freshStats);
      showSnack(context,
          status == 'blocked' ? 'Đã khóa tài khoản' : 'Đã mở khóa tài khoản');
    }
  }

  Future<void> deleteUser(Map<String, dynamic> user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa tài khoản?'),
        content: Text('Xóa tài khoản "${user['name']}" và dữ liệu liên quan?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.api.adminDeleteUser('${user['id']}');
    await loadUsers();
    await loadProducts();
    final freshStats = await widget.api.adminStats();
    if (mounted) {
      setState(() => stats = freshStats);
      showSnack(context, 'Đã xóa tài khoản');
    }
  }
}

class StatDetailSheet extends StatefulWidget {
  const StatDetailSheet({super.key, required this.api, required this.info});

  final ApiClient api;
  final StatInfo info;

  @override
  State<StatDetailSheet> createState() => _StatDetailSheetState();
}

class _StatDetailSheetState extends State<StatDetailSheet> {
  bool loading = true;
  Map<String, dynamic> detail = {};
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final loaded = await widget.api.adminDetail(widget.info.type);
      if (!mounted) return;
      setState(() {
        detail = loaded;
        items = List<Map<String, dynamic>>.from(loaded['items'] ?? []);
      });
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${detail['title'] ?? widget.info.label}',
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${items.length} mục',
                            style: const TextStyle(
                              color: muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tải lại',
                      onPressed: loading ? null : load,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? const Center(
                            child: Text('Không có dữ liệu chi tiết',
                                style: TextStyle(color: muted)),
                          )
                        : ListView.builder(
                            controller: controller,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                            itemCount: items.length,
                            itemBuilder: (_, index) =>
                                _detailItem(items[index]),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailItem(Map<String, dynamic> item) {
    return switch (widget.info.type) {
      'users' || 'blockedUsers' => _userItem(item),
      'products' || 'pending' || 'approved' || 'hidden' => _productItem(item),
      'orders' || 'revenue' => _orderItem(item),
      'chats' => _chatItem(item),
      'reviews' => _reviewItem(item),
      _ => _genericItem(item),
    };
  }

  Widget _userItem(Map<String, dynamic> user) {
    final blocked = user['status'] == 'blocked';
    return _detailCard(
      child: Row(
        children: [
          UserAvatar(user: user, radius: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${user['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('${user['email']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  'Bài đăng ${user['productCount'] ?? 0}  |  Đơn hàng ${user['orderCount'] ?? 0}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          _miniChip(blocked ? 'Khóa' : '${user['role'] ?? 'user'}',
              blocked ? danger : brand),
        ],
      ),
    );
  }

  Widget _productItem(Map<String, dynamic> product) {
    final seller = Map<String, dynamic>.from(product['seller'] ?? {});
    return _detailCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              '${product['image']}',
              width: 74,
              height: 74,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: Color(0xFFEAF1F0),
                child: SizedBox(width: 74, height: 74),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${product['title']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 8),
                    Text(currency(product['price']),
                        style: const TextStyle(
                            color: danger, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 5),
                Text('${seller['name'] ?? 'Người bán'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 6),
                _miniChip(_statusText('${product['status']}'), brandDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderItem(Map<String, dynamic> order) {
    final buyer = Map<String, dynamic>.from(order['buyer'] ?? {});
    final items = List<Map<String, dynamic>>.from(order['items'] ?? []);
    final titles = items.map((item) => '${item['title']}').join(', ');
    return _detailCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE4F7F3),
            foregroundColor: brand,
            child: Icon(Icons.receipt_long_outlined),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${order['id']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    Text(currency(order['total']),
                        style: const TextStyle(
                            color: danger, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${buyer['name'] ?? 'Người mua'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(titles.isEmpty ? 'Không có sản phẩm' : titles,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatItem(Map<String, dynamic> chat) {
    final buyer = Map<String, dynamic>.from(chat['buyer'] ?? {});
    final seller = Map<String, dynamic>.from(chat['seller'] ?? {});
    final product = Map<String, dynamic>.from(chat['product'] ?? {});
    final last = Map<String, dynamic>.from(chat['lastMessage'] ?? {});
    final preview = '${last['text'] ?? ''}'.isEmpty
        ? (last['imageUrl'] == null ? 'Chưa có tin nhắn' : 'Tin nhắn ảnh')
        : '${last['text']}';
    return _detailCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE4F7F3),
            foregroundColor: brand,
            child: Icon(Icons.chat_bubble_outline_rounded),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${buyer['name'] ?? 'Người mua'} - ${seller['name'] ?? 'Người bán'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('${product['title'] ?? 'Sản phẩm đã xóa'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 4),
                Text('$preview  |  ${chat['messageCount'] ?? 0} tin',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewItem(Map<String, dynamic> review) {
    final buyer = Map<String, dynamic>.from(review['buyer'] ?? {});
    final seller = Map<String, dynamic>.from(review['seller'] ?? {});
    return _detailCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFFFF4D6),
            foregroundColor: Color(0xFF9B6500),
            child: Icon(Icons.star_rounded),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${buyer['name'] ?? 'Người mua'} đánh giá ${seller['name'] ?? 'Người bán'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('${review['rating']} sao',
                    style: const TextStyle(
                        color: Color(0xFF9B6500), fontWeight: FontWeight.w900)),
                if ('${review['comment'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('${review['comment']}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _genericItem(Map<String, dynamic> item) {
    return _detailCard(
      child: Text(
        item.toString(),
        style: const TextStyle(color: muted),
      ),
    );
  }

  Widget _detailCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: child,
    );
  }

  Widget _miniChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String _statusText(String status) {
    return status == 'approved'
        ? 'Đã duyệt'
        : status == 'pending'
            ? 'Chờ duyệt'
            : 'Đã ẩn';
  }
}
