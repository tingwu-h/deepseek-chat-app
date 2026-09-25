import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:deepseek_chat/models/chat_attachment.dart';

/// 选择附件的异常：message 已经是可以直接展示给用户的中文。
class AttachmentException implements Exception {
  AttachmentException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 负责「选图片 / 选文件 → 存进应用私有目录 → 返回 ChatAttachment」。
///
/// 为什么不直接用用户选中的原路径：Android 上选中的文件常常在一个临时缓存目录里，
/// 系统随时可能清理，历史记录里的图片就会变成裂图。所以统一复制一份到自己目录。
class AttachmentService {
  AttachmentService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// 文本类文件允许的扩展名（DeepSeek 不接受文件本身，只接受文本内容）
  static const List<String> textExtensions = <String>[
    'txt', 'md', 'markdown', 'json', 'csv', 'log', 'yaml', 'yml', 'xml', 'html',
    'dart', 'js', 'ts', 'py', 'java', 'kt', 'c', 'cpp', 'h', 'cs', 'go', 'rs',
    'swift', 'php', 'rb', 'sh', 'sql', 'ini', 'conf', 'properties', 'gradle',
  ];

  /// 单个文本文件最多读多少字符（避免把接口撑爆）
  static const int maxTextChars = 60000;

  /// 选取图片（可多选）
  Future<List<ChatAttachment>> pickImages() async {
    final List<XFile> picked = await _picker.pickMultiImage(
      // 限制尺寸与质量：base64 会放大约 1/3，压一压能显著减小请求体
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked.isEmpty) return <ChatAttachment>[];

    final List<ChatAttachment> result = <ChatAttachment>[];
    for (final XFile x in picked) {
      final File saved = await _persist(File(x.path), x.name);
      result.add(ChatAttachment(
        name: x.name,
        path: saved.path,
        kind: 'image',
        size: await saved.length(),
      ));
    }
    return result;
  }

  /// 选取文件（文本类直接读入内容；图片走图像通道）
  ///
  /// 注意：file_picker 13.x 起 API 变了——
  /// 不再有 FilePickerResult，pickFiles 直接返回 List<PlatformFile>，
  /// PlatformFile.size 也换成了 await file.length()。
  /// 用 8.x 的写法会编译不过，而 8.x 又因为 compileSdk 34 无法在本项目构建。
  Future<List<ChatAttachment>> pickFiles() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.any,
    );
    if (files.isEmpty) return <ChatAttachment>[];

    final List<ChatAttachment> out = <ChatAttachment>[];
    final List<String> rejected = <String>[];

    for (final PlatformFile f in files) {
      final String? p = f.path;
      if (p == null) continue;
      final String ext = f.name.toLowerCase().contains('.')
          ? f.name.toLowerCase().split('.').last
          : '';
      final bool isImage = <String>['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp']
          .contains(ext);

      if (isImage) {
        final File saved = await _persist(File(p), f.name);
        out.add(ChatAttachment(
          name: f.name,
          path: saved.path,
          kind: 'image',
          size: await saved.length(),
        ));
        continue;
      }

      if (!textExtensions.contains(ext)) {
        rejected.add(f.name);
        continue;
      }

      // 文本类：读进来（限制长度）
      String content;
      try {
        content = await File(p).readAsString();
      } catch (_) {
        // 不是 UTF-8 就当二进制，放弃
        rejected.add('${f.name}（无法按文本读取）');
        continue;
      }
      if (content.length > maxTextChars) {
        content = '${content.substring(0, maxTextChars)}\n…（内容过长，已截断）';
      }
      out.add(ChatAttachment(
        name: f.name,
        path: p,
        kind: 'text',
        size: (f.lengthSync() ?? await f.length()) ?? content.length,
        textContent: content,
      ));
    }

    if (out.isEmpty && rejected.isNotEmpty) {
      throw AttachmentException(
        '不支持这些文件：${rejected.join('、')}\n'
        '图片支持 jpg/png/gif/webp；文档支持 txt/md/json/csv/代码等纯文本。',
      );
    }
    return out;
  }

  /// 复制到应用私有目录 attachments/
  Future<File> _persist(File src, String name) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/attachments');
    if (!await dir.exists()) await dir.create(recursive: true);
    final String safe =
        '${DateTime.now().microsecondsSinceEpoch}_${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';
    final File dst = File('${dir.path}/$safe');
    await src.copy(dst.path);
    return dst;
  }
}
