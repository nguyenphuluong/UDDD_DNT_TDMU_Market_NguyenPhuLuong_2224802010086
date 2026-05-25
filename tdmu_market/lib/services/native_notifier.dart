import 'package:flutter/services.dart';

class NativeNotifier {
  static const _channel = MethodChannel('tdmu_marketplace/notifications');

  static Future<void> show({
    required String title,
    required String body,
  }) async {
    await _channel.invokeMethod<void>('show', {
      'title': title,
      'body': body,
    });
  }
}
