import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ui_helpers.dart';
import '../services/api_client.dart';
import '../services/native_image_picker.dart';
import '../widgets/user_avatar.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.api,
    required this.chat,
    this.onChanged,
  });

  final ApiClient api;
  final Map<String, dynamic> chat;
  final Future<void> Function({bool announce})? onChanged;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  StreamSubscription<Map<String, dynamic>>? streamSub;
  Timer? fallbackTimer;
  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  bool sendingImage = false;

  @override
  void initState() {
    super.initState();
    load().then((_) => _connectRealtime());
    fallbackTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => load(silent: true));
  }

  @override
  void dispose() {
    streamSub?.cancel();
    fallbackTimer?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    final loaded = await widget.api.messages('${widget.chat['id']}');
    await widget.onChanged?.call(announce: false);
    if (!mounted) return;
    setState(() {
      messages = loaded;
      loading = false;
    });
    if (!silent) _scrollToBottom();
  }

  void _connectRealtime() {
    streamSub?.cancel();
    streamSub = widget.api.chatStream('${widget.chat['id']}').listen(
          _addMessage,
          onError: (_) {},
          cancelOnError: false,
        );
  }

  void _addMessage(Map<String, dynamic> message) {
    if (messages.any((item) => item['id'] == message['id'])) return;
    if (!mounted) return;
    setState(() => messages.add(message));
    final other = Map<String, dynamic>.from(widget.chat['other'] ?? {});
    if (message['senderId'] == other['id']) {
      widget.api.markChatRead('${widget.chat['id']}');
      widget.onChanged?.call(announce: false);
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final other = widget.chat['other'] ?? {};
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${other['name'] ?? 'Chat'}'),
            const Text(
              'Đang chat trực tuyến',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: UserAvatar(
                user: Map<String, dynamic>.from(other),
                radius: 18,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: messages.length,
                    itemBuilder: (_, index) {
                      final message = messages[index];
                      final mine = message['senderId'] != other['id'];
                      final imageUrl = '${message['imageUrl'] ?? ''}';
                      final text = '${message['text'] ?? ''}';
                      final hasImage = imageUrl.isNotEmpty;
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * .78),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: EdgeInsets.all(hasImage ? 6 : 12),
                          decoration: BoxDecoration(
                            color: hasImage
                                ? Colors.white
                                : mine
                                    ? brand
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasImage)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (_, child, progress) {
                                      if (progress == null) return child;
                                      return const SizedBox(
                                        height: 180,
                                        child: Center(
                                            child: CircularProgressIndicator()),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 160,
                                      alignment: Alignment.center,
                                      color: const Color(0xFFEAF1F0),
                                      child: const Icon(
                                          Icons.broken_image_outlined),
                                    ),
                                  ),
                                ),
                              if (text.isNotEmpty) ...[
                                if (hasImage) const SizedBox(height: 8),
                                Padding(
                                  padding: EdgeInsets.all(hasImage ? 6 : 0),
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      color: !hasImage && mine
                                          ? Colors.white
                                          : ink,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Gửi ảnh',
                    onPressed: sendingImage ? null : sendImage,
                    icon: sendingImage
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_outlined),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => send(),
                      decoration:
                          const InputDecoration(hintText: 'Nhập tin nhắn...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: send, child: const Icon(Icons.send_rounded)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    try {
      final message =
          await widget.api.sendMessage('${widget.chat['id']}', text);
      _addMessage(message);
    } catch (error) {
      input.text = text;
      if (mounted) showSnack(context, '$error');
    }
  }

  Future<void> sendImage() async {
    try {
      final picked = await NativeImagePicker.pickImage();
      if (picked == null) return;
      setState(() => sendingImage = true);
      final imageUrl = await widget.api.uploadImage('${picked['dataUrl']}');
      final message = await widget.api
          .sendMessage('${widget.chat['id']}', '', imageUrl: imageUrl);
      _addMessage(message);
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => sendingImage = false);
    }
  }
}
