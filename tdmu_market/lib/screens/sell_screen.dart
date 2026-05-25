import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ui_helpers.dart';
import '../services/api_client.dart';
import '../services/native_image_picker.dart';

class SellScreen extends StatefulWidget {
  const SellScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  final category = TextEditingController(text: 'Sách và tài liệu');
  final price = TextEditingController();
  final condition = TextEditingController(text: 'Đã sử dụng tốt');
  final location = TextEditingController(text: 'Thư viện TDMU');
  String? imageUrl;
  String? imageName;
  bool loading = false;
  bool uploadingImage = false;

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    category.dispose();
    price.dispose();
    condition.dispose();
    location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: cardDecoration(),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Đăng bán sản phẩm',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              SizedBox(height: 6),
              Text(
                  'Bài đăng sẽ ở trạng thái chờ duyệt trước khi xuất hiện trong chợ.',
                  style: TextStyle(color: muted)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Form(
          key: formKey,
          child: Column(
            children: [
              _input(title, 'Tên sản phẩm', required: true),
              _input(description, 'Mô tả', maxLines: 4, required: true),
              _input(category, 'Danh mục', required: true),
              _input(price, 'Giá bán',
                  keyboardType: TextInputType.number, required: true),
              _input(condition, 'Tình trạng', required: true),
              _input(location, 'Địa điểm giao dịch', required: true),
              _imagePicker(),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: loading || uploadingImage ? null : submit,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: brand),
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: const Text('Gửi bài chờ duyệt'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _input(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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

  Widget _imagePicker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: uploadingImage ? null : pickImage,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFE4F7F3),
                    child: uploadingImage
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.photo_library_outlined,
                            color: brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ảnh sản phẩm',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(
                          imageName ?? 'Chọn ảnh từ điện thoại',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: muted),
                ],
              ),
              if (imageUrl != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Color(0xFFEAF1F0)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> pickImage() async {
    try {
      final picked = await NativeImagePicker.pickImage();
      if (picked == null) return;
      setState(() => uploadingImage = true);
      final uploadedUrl = await widget.api.uploadImage('${picked['dataUrl']}');
      if (!mounted) return;
      setState(() {
        imageUrl = uploadedUrl;
        imageName = '${picked['fileName'] ?? 'Ảnh sản phẩm'}';
      });
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => uploadingImage = false);
    }
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    if (imageUrl == null) {
      showSnack(context, 'Vui lòng chọn ảnh sản phẩm');
      return;
    }
    setState(() => loading = true);
    try {
      await widget.api.createProduct({
        'title': title.text.trim(),
        'description': description.text.trim(),
        'category': category.text.trim(),
        'price': num.tryParse(price.text.trim()) ?? 0,
        'condition': condition.text.trim(),
        'location': location.text.trim(),
        'image': imageUrl,
      });
      if (!mounted) return;
      showSnack(context, 'Đã gửi bài, vui lòng chờ admin duyệt');
      title.clear();
      description.clear();
      price.clear();
      setState(() {
        imageUrl = null;
        imageName = null;
      });
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}
