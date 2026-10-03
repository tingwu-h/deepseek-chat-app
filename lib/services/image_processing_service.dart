import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Encoded image output shared by attachments and chat backgrounds.
class ImageProcessingService {
  static const maxBytes = 5 * 1024 * 1024;
  static const _channel = MethodChannel('deepseek_chat/platform');

  static Future<File> save(Uint8List png) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = await Directory('${base.path}/attachments')
        .create(recursive: true);
    final stem = '${dir.path}/image_${DateTime.now().microsecondsSinceEpoch}';
    final original = await File('$stem.png').writeAsBytes(png, flush: true);
    if (png.length <= maxBytes) return original;
    try {
      final path = await _channel.invokeMethod<String>('compressImage', {
        'path': original.path,
        'output': '$stem.jpg',
      });
      if (path == null) throw const FormatException('Image compression failed');
      final result = File(path);
      if (await result.length() > maxBytes) {
        throw const FormatException('Image exceeds 5 MB');
      }
      await original.delete();
      return result;
    } catch (_) {
      if (await original.exists()) await original.delete();
      final partial = File('$stem.jpg');
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }
}
