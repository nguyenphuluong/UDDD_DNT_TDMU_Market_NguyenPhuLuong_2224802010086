import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/ui_helpers.dart';
import '../services/api_client.dart';
import '../services/native_image_picker.dart';
import 'admin_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen(
      {super.key,
      required this.api,
      required this.user,
      required this.onUserChanged,
      required this.onLogout});

  final ApiClient api;
  final Map<String, dynamic> user;
  final ValueChanged<Map<String, dynamic>> onUserChanged;
  final VoidCallback onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Map<String, dynamic> user;
  List<Map<String, dynamic>> myProducts = [];
  bool loadingProducts = true;

  @override
  void initState() {
    super.initState();
    user = Map<String, dynamic>.from(widget.user);
    loadMyProducts();
  }

  Future<void> loadMyProducts() async {
    setState(() => loadingProducts = true);
    try {
      myProducts = await widget.api.myProducts();
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loadingProducts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = user['role'] == 'admin';
    return RefreshIndicator(
      onRefresh: loadMyProducts,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _profileCard(),
          const SizedBox(height: 14),
          _accountActions(),
          const SizedBox(height: 14),
          if (isAdmin)
            AdminPanel(api: widget.api, currentUser: user)
          else
            _myProductsSection(),
        ],
      ),
    );
  }

  Widget _profileCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        children: [
          ProfileAvatar(user: user, radius: 44, fontSize: 24),
          const SizedBox(height: 12),
          Text('${user['name']}',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center),
          Text('${user['email']}', style: const TextStyle(color: muted)),
          const SizedBox(height: 10),
          Text('${user['major'] ?? 'Sinh viên TDMU'}',
              textAlign: TextAlign.center),
          if ('${user['bio'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${user['bio']}',
                style: const TextStyle(color: muted),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _accountActions() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tài khoản',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Mã sinh viên'),
            subtitle: Text('${user['studentId'] ?? ''}'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: const Text('Địa điểm giao dịch'),
            subtitle: Text('${user['location'] ?? 'TDMU'}'),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: openEditProfile,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Chỉnh sửa'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Đăng xuất'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _myProductsSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('Bài đăng của tôi',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900))),
              IconButton(
                  onPressed: loadMyProducts, icon: const Icon(Icons.refresh)),
            ],
          ),
          const Text(
              'Bài chờ duyệt chỉ hiện ở đây, không hiện ngoài chợ chung.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          if (loadingProducts) const Center(child: CircularProgressIndicator()),
          if (!loadingProducts && myProducts.isEmpty)
            const Text('Bạn chưa có bài đăng nào.'),
          ...myProducts.map(productCard),
        ],
      ),
    );
  }

  Widget productCard(Map<String, dynamic> product) {
    final status = '${product['status']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network('${product['image']}',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFFEAF1F0))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
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
                const SizedBox(height: 8),
                Text('${product['title']}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('${product['description']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => openEditProduct(product),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Sửa'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: danger),
                        onPressed: () => deleteProduct(product),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Xóa'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final text = status == 'approved'
        ? 'Đã duyệt'
        : status == 'pending'
            ? 'Chờ duyệt'
            : 'Đã ẩn';
    final color = status == 'approved'
        ? brand
        : status == 'pending'
            ? const Color(0xFF9B6500)
            : danger;
    return Chip(
      label: Text(text),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide.none,
    );
  }

  Future<void> openEditProfile() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EditProfileSheet(user: user, api: widget.api),
    );
    if (result == null) return;
    setState(() => user = result);
    widget.onUserChanged(result);
    if (mounted) showSnack(context, 'Đã cập nhật thông tin cá nhân');
  }

  Future<void> openEditProduct(Map<String, dynamic> product) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EditProductSheet(product: product, api: widget.api),
    );
    if (saved == true) {
      await loadMyProducts();
      if (mounted) {
        showSnack(context, 'Đã cập nhật bài đăng, vui lòng chờ duyệt lại');
      }
    }
  }

  Future<void> deleteProduct(Map<String, dynamic> product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa bài đăng?'),
        content: Text('Bạn muốn xóa "${product['title']}"?'),
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
    await widget.api.deleteProduct('${product['id']}');
    await loadMyProducts();
    if (mounted) showSnack(context, 'Đã xóa bài đăng');
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(
      {super.key,
      required this.user,
      required this.radius,
      required this.fontSize});

  final Map<String, dynamic> user;
  final double radius;
  final double fontSize;

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
      backgroundColor: danger,
      backgroundImage: provider,
      child: provider != null
          ? null
          : Text('${user['avatar'] ?? 'SV'}',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900)),
    );
  }

  Uint8List _decodeDataImage(String value) {
    final comma = value.indexOf(',');
    return base64Decode(comma == -1 ? value : value.substring(comma + 1));
  }
}

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key, required this.user, required this.api});

  final Map<String, dynamic> user;
  final ApiClient api;

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController studentId;
  late final TextEditingController major;
  late final TextEditingController phone;
  late final TextEditingController location;
  late final TextEditingController bio;
  late final TextEditingController avatar;
  String avatarImage = '';
  bool saving = false;
  bool uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: '${widget.user['name'] ?? ''}');
    studentId =
        TextEditingController(text: '${widget.user['studentId'] ?? ''}');
    major = TextEditingController(text: '${widget.user['major'] ?? ''}');
    phone = TextEditingController(text: '${widget.user['phone'] ?? ''}');
    location =
        TextEditingController(text: '${widget.user['location'] ?? 'TDMU'}');
    bio = TextEditingController(text: '${widget.user['bio'] ?? ''}');
    avatarImage = '${widget.user['avatarImage'] ?? ''}';
    avatar = TextEditingController(text: avatarImage);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('Chỉnh sửa cá nhân',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            Center(
              child: Stack(
                children: [
                  ProfileAvatar(
                      user: {...widget.user, 'avatarImage': avatarImage},
                      radius: 46,
                      fontSize: 24),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Material(
                      color: brand,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: uploadingAvatar ? null : pickAvatar,
                        child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: uploadingAvatar
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.image_outlined,
                                  color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: avatar,
              decoration: const InputDecoration(
                labelText: 'Link ảnh đại diện',
                hintText: 'https://...',
              ),
              onChanged: (value) => setState(() => avatarImage = value.trim()),
            ),
            if (avatarImage.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() {
                  avatarImage = '';
                  avatar.clear();
                }),
                icon: const Icon(Icons.close),
                label: const Text('Gỡ ảnh đại diện'),
              ),
            ],
            const SizedBox(height: 12),
            _input(name, 'Họ tên', required: true),
            _input(studentId, 'Mã sinh viên', required: true),
            _input(major, 'Ngành học', required: true),
            _input(phone, 'Số điện thoại'),
            _input(location, 'Địa điểm giao dịch'),
            _input(bio, 'Giới thiệu', maxLines: 3),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: saving ? null : save,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Lưu thông tin'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController controller, String label,
      {bool required = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? 'Không được bỏ trống'
                : null
            : null,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final updated = await widget.api.updateMe({
        'name': name.text.trim(),
        'studentId': studentId.text.trim(),
        'major': major.text.trim(),
        'phone': phone.text.trim(),
        'location': location.text.trim(),
        'bio': bio.text.trim(),
        'avatarImage': avatar.text.trim(),
      });
      if (mounted) Navigator.pop(context, updated);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> pickAvatar() async {
    try {
      final picked = await NativeImagePicker.pickImage();
      if (picked == null) return;
      setState(() => uploadingAvatar = true);
      final uploadedUrl = await widget.api.uploadImage('${picked['dataUrl']}');
      if (!mounted) return;
      setState(() {
        avatarImage = uploadedUrl;
        avatar.text = uploadedUrl;
      });
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => uploadingAvatar = false);
    }
  }
}

class EditProductSheet extends StatefulWidget {
  const EditProductSheet({super.key, required this.product, required this.api});

  final Map<String, dynamic> product;
  final ApiClient api;

  @override
  State<EditProductSheet> createState() => _EditProductSheetState();
}

class _EditProductSheetState extends State<EditProductSheet> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController description;
  late final TextEditingController category;
  late final TextEditingController price;
  late final TextEditingController condition;
  late final TextEditingController location;
  late final TextEditingController image;
  bool saving = false;
  bool uploadingImage = false;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: '${widget.product['title'] ?? ''}');
    description =
        TextEditingController(text: '${widget.product['description'] ?? ''}');
    category =
        TextEditingController(text: '${widget.product['category'] ?? ''}');
    price = TextEditingController(text: '${widget.product['price'] ?? ''}');
    condition =
        TextEditingController(text: '${widget.product['condition'] ?? ''}');
    location =
        TextEditingController(text: '${widget.product['location'] ?? ''}');
    image = TextEditingController(text: '${widget.product['image'] ?? ''}');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('Chỉnh sửa bài đăng',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            _input(title, 'Tên sản phẩm', required: true),
            _input(description, 'Mô tả', maxLines: 4, required: true),
            _input(category, 'Danh mục', required: true),
            _input(price, 'Giá bán',
                required: true, keyboardType: TextInputType.number),
            _input(condition, 'Tình trạng', required: true),
            _input(location, 'Địa điểm', required: true),
            OutlinedButton.icon(
              onPressed: uploadingImage ? null : pickProductImage,
              icon: uploadingImage
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_library_outlined),
              label: const Text('Chọn ảnh từ điện thoại'),
            ),
            const SizedBox(height: 10),
            if (image.text.trim().isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  image.text.trim(),
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 150,
                    color: bg,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            _input(image, 'Link ảnh'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: saving ? null : save,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Lưu bài đăng'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController controller, String label,
      {bool required = false, int maxLines = 1, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? 'Không được bỏ trống'
                : null
            : null,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.api.updateProduct('${widget.product['id']}', {
        'title': title.text.trim(),
        'description': description.text.trim(),
        'category': category.text.trim(),
        'price': num.tryParse(price.text.trim()) ?? 0,
        'condition': condition.text.trim(),
        'location': location.text.trim(),
        'image': image.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> pickProductImage() async {
    try {
      final picked = await NativeImagePicker.pickImage();
      if (picked == null) return;
      setState(() => uploadingImage = true);
      final uploadedUrl = await widget.api.uploadImage('${picked['dataUrl']}');
      if (!mounted) return;
      setState(() {
        image.text = uploadedUrl;
      });
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => uploadingImage = false);
    }
  }
}
