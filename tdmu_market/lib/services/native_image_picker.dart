import 'package:flutter/services.dart';

class NativeImagePicker {
  static const _channel = MethodChannel('tdmu_marketplace/image_picker');

  static Future<Map<String, dynamic>?> pickImage() async {
    final result =
        await _channel.invokeMethod<Map<dynamic, dynamic>>('pickImage');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }
}
