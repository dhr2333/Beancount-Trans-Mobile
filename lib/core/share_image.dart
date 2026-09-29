import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 把 [widget] 离屏渲染成 PNG，支持超过一屏高度的长图。
///
/// 做法：往根 Overlay 临时插入一个 [OverlayEntry]，用 [UnconstrainedBox] 放开高度
/// 约束，让 [RepaintBoundary] 按内容自然高度完成布局与绘制后取图，最后移除。
/// 取图前按 [maxDimension] 反推 pixelRatio，避免长图撞上设备位图尺寸上限。
Future<Uint8List?> renderWidgetToPng(
  BuildContext context,
  Widget widget, {
  required double width,
  double maxPixelRatio = 2,
  double maxDimension = 10000,
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;

  final boundaryKey = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 0,
      top: 0,
      child: Transform.translate(
        // 移出可视区：只参与布局与绘制，不影响当前界面
        offset: const Offset(0, -100000),
        child: SizedBox(
          width: width,
          child: UnconstrainedBox(
            constrainedAxis: Axis.horizontal,
            alignment: Alignment.topLeft,
            child: RepaintBoundary(key: boundaryKey, child: widget),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  try {
    // 等待插入后的这一帧完成布局与绘制
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || boundary.size.isEmpty) return null;

    final height = boundary.size.height;
    final ratio = height <= 0 ? maxPixelRatio : maxDimension / height;
    final pixelRatio = ratio.clamp(1.0, maxPixelRatio);

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// 把 PNG 写入临时目录并调起系统分享面板。
Future<void> sharePngBytes(
  Uint8List bytes, {
  required String fileName,
  String? text,
}) async {
  final dir = await getTemporaryDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: text,
      title: 'Beancount-Trans',
    ),
  );
}
