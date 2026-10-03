import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:deepseek_chat/services/image_processing_service.dart';

/// A bounded decode keeps large camera images out of the full-resolution heap.
class ImageEditorPage extends StatefulWidget {
  const ImageEditorPage({
    super.key,
    required this.path,
    this.background = false,
  });
  final String path;
  final bool background;

  static Future<File?> open(
    BuildContext context,
    String path, {
    bool background = false,
  }) => Navigator.of(context).push<File>(
    MaterialPageRoute(
      builder: (_) => ImageEditorPage(path: path, background: background),
    ),
  );

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  ui.Image? _image;
  String? _error;
  double _zoom = 1;
  double _startZoom = 1;
  Offset _center = const Offset(.5, .5);
  double? _ratio;
  double _outputScale = 1;
  bool _saving = false;

  String _text(String cn, String tw, String en) {
    final locale = Localizations.localeOf(context);
    return locale.languageCode == 'en'
        ? en
        : locale.countryCode == 'TW'
        ? tw
        : cn;
  }

  @override
  void initState() {
    super.initState();
    _ratio = widget.background ? 9 / 16 : null;
    _load();
  }

  Future<void> _load() async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      final file = File(widget.path);
      if (await file.length() > 100 * 1024 * 1024) {
        throw const FormatException();
      }
      buffer = await ui.ImmutableBuffer.fromFilePath(widget.path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = math.min(
        1.0,
        2048 / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      final image = (await codec.getNextFrame()).image;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      if (mounted) setState(() => _error = 'decode');
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Rect get _crop {
    final image = _image!;
    final ratio = _ratio ?? image.width / image.height;
    double width = image.width.toDouble();
    double height = width / ratio;
    if (height > image.height) {
      height = image.height.toDouble();
      width = height * ratio;
    }
    width /= _zoom;
    height /= _zoom;
    final left = (_center.dx * image.width - width / 2).clamp(
      0.0,
      image.width - width,
    );
    final top = (_center.dy * image.height - height / 2).clamp(
      0.0,
      image.height - height,
    );
    return Rect.fromLTWH(left, top, width, height);
  }

  Future<void> _save() async {
    if (_saving || _image == null) return;
    setState(() => _saving = true);
    ui.Image? output;
    ui.Picture? picture;
    try {
      final crop = _crop;
      final scale = math.min(
        _outputScale,
        2048 / math.max(crop.width, crop.height),
      );
      final width = math.max(1, (crop.width * scale).round());
      final height = math.max(1, (crop.height * scale).round());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        _image!,
        crop,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      picture = recorder.endRecording();
      output = await picture.toImage(width, height);
      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw const FormatException();
      final file = await ImageProcessingService.save(
        bytes.buffer.asUint8List(),
      );
      if (!mounted) {
        await file.delete();
        return;
      }
      Navigator.pop(context, file);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                '图片处理失败，请换一张图片重试',
                '圖片處理失敗，請換一張圖片重試',
                'Could not process this image. Try another image.',
              ),
            ),
          ),
        );
        setState(() => _saving = false);
      }
    } finally {
      output?.dispose();
      picture?.dispose();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_text('调整图片', '調整圖片', 'Adjust image')),
          actions: [
            TextButton(
              onPressed: image == null || _saving ? null : _save,
              child: Text(_text('使用', '使用', 'Use')),
            ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Text(
                  _text(
                    '无法读取图片，请选择其他图片',
                    '無法讀取圖片，請選擇其他圖片',
                    'Cannot read this image. Choose another image.',
                  ),
                ),
              )
            : image == null
            ? const Center(child: CircularProgressIndicator())
            : AbsorbPointer(
                absorbing: _saving,
                child: Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final crop = _crop;
                          final size = applyBoxFit(
                            BoxFit.contain,
                            crop.size,
                            Size(
                              constraints.maxWidth - 32,
                              constraints.maxHeight - 32,
                            ),
                          ).destination;
                          return Center(
                            child: GestureDetector(
                              onScaleStart: (_) => _startZoom = _zoom,
                              onScaleUpdate: (details) => setState(() {
                                final rect = _crop;
                                _zoom = (_startZoom * details.scale).clamp(
                                  1,
                                  8,
                                );
                                final c =
                                    rect.center -
                                    Offset(
                                      details.focalPointDelta.dx *
                                          rect.width /
                                          size.width,
                                      details.focalPointDelta.dy *
                                          rect.height /
                                          size.height,
                                    );
                                _center = Offset(
                                  (c.dx / image.width).clamp(0, 1),
                                  (c.dy / image.height).clamp(0, 1),
                                );
                              }),
                              child: ClipRect(
                                child: CustomPaint(
                                  size: size,
                                  painter: _CropPainter(image, crop),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_saving) const LinearProgressIndicator(),
                    Flexible(
                      flex: 0,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _text(
                                  '拖动、双指缩放，调整裁剪范围',
                                  '拖動、雙指縮放，調整裁剪範圍',
                                  'Drag or pinch to adjust the crop',
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final choice in <(double?, String)>[
                                    (null, _text('原比例', '原比例', 'Original')),
                                    (1, '1:1'),
                                    (9 / 16, '9:16'),
                                    (16 / 9, '16:9'),
                                  ])
                                    ChoiceChip(
                                      label: Text(choice.$2),
                                      selected: _ratio == choice.$1,
                                      onSelected: (_) => setState(() {
                                        _ratio = choice.$1;
                                        _zoom = 1;
                                        _center = const Offset(.5, .5);
                                      }),
                                    ),
                                ],
                              ),
                              Row(
                                children: [
                                  Text(_text('缩放', '縮放', 'Zoom')),
                                  Expanded(
                                    child: Slider(
                                      value: _zoom,
                                      min: 1,
                                      max: 8,
                                      onChanged: (v) =>
                                          setState(() => _zoom = v),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Text(_text('放大输出', '放大輸出', 'Enlarge output')),
                                  const SizedBox(width: 12),
                                  DropdownButton<double>(
                                    value: _outputScale,
                                    items: [
                                      for (final v in [1.0, 2.0, 4.0])
                                        DropdownMenuItem(
                                          value: v,
                                          child: Text('${v.toInt()}×'),
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _outputScale = v!),
                                  ),
                                ],
                              ),
                              Text(
                                _text(
                                  '超过 5 MB 自动压缩；放大不会增加原图细节',
                                  '超過 5 MB 自動壓縮；放大不會增加原圖細節',
                                  'Images over 5 MB are compressed; enlarging does not add detail',
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.crop);
  final ui.Image image;
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFF202020), BlendMode.src);
    canvas.drawImageRect(
      image,
      crop,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.drawRect(
      (Offset.zero & size).deflate(1),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.crop != crop || oldDelegate.image != image;
}
