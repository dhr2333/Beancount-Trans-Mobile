import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/update_service.dart';
import 'markdown_content.dart';

/// 展示更新弹窗：版本对比 + 更新说明 + 应用内下载安装。
///
/// [manual] 表示由用户主动触发（「我的」页检查更新），文案上更强调当前状态；
/// 自动检查失败不应打扰用户，因此本函数只负责展示成功拿到的更新信息。
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  bool manual = false,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(info: info, manual: manual),
  );
}

/// 弹窗所处的阶段。
enum _Phase { idle, downloading, ready, failed }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info, required this.manual});

  final UpdateInfo info;
  final bool manual;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  String _error = '';

  CancelToken? _cancelToken;

  /// 已下载完成的安装包，供「重新安装」复用。
  File? _apkFile;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    final token = CancelToken();
    setState(() {
      _cancelToken = token;
      _phase = _Phase.downloading;
      _progress = 0;
      _error = '';
    });

    File? downloaded;
    try {
      downloaded = await UpdateService.instance.downloadApk(
        widget.info,
        cancelToken: token,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
    } on UpdateException catch (error) {
      if (!mounted) return;
      // 用户主动取消：安静回到可重试状态
      if (token.isCancelled) {
        setState(() => _phase = _Phase.idle);
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _error = error.message;
      });
      return;
    } finally {
      if (mounted && _cancelToken == token) _cancelToken = null;
    }

    if (!mounted) return;
    _apkFile = downloaded;
    setState(() => _phase = _Phase.ready);
    await _install(downloaded);
  }

  /// 调起系统安装：失败只提示，已下载的安装包仍留给「重新安装」复用。
  Future<void> _install(File file) async {
    try {
      await UpdateService.instance.installApk(file);
      if (mounted) setState(() => _error = '');
    } on UpdateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  /// 下载完成后手动再调起一次安装（安装器可能被用户提前关闭）。
  Future<void> _installAgain() async {
    final file = _apkFile;
    if (file == null || !await file.exists()) {
      _apkFile = null;
      await _startDownload();
      return;
    }
    await _install(file);
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    setState(() => _phase = _Phase.idle);
  }

  Future<void> _copyDownloadUrl() async {
    final url = widget.info.apkUrl?.isNotEmpty ?? false
        ? widget.info.apkUrl!
        : widget.info.releaseUrl;
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('下载链接已复制')));
  }

  /// [skipped] 为 true 表示用户选择「稍后」，本次版本不再自动提醒。
  Future<void> _close({bool skipped = false}) async {
    if (skipped) {
      await UpdateService.instance.skipVersion(widget.info.latestVersion);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('发现新版本'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVersionRow(theme),
            const SizedBox(height: 14),
            Text('更新内容', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Flexible(child: _buildNotes(theme)),
            if (_phase == _Phase.downloading) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(
                '正在下载 ${(_progress * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_phase == _Phase.ready) ...[
              const SizedBox(height: 12),
              Text(
                // 安装器调起失败时把原因显示出来，安装包已下载可直接重试
                _error.isEmpty ? '安装包已下载，请在系统安装界面完成安装。' : _error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _error.isEmpty
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ),
            ],
            if (_phase == _Phase.failed) ...[
              const SizedBox(height: 12),
              Text(
                _error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (!widget.info.canInstallInApp) ...[
              const SizedBox(height: 12),
              Text(
                '当前环境不支持应用内安装，可复制下载链接后前往浏览器下载。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: _buildActions(theme),
    );
  }

  Widget _buildVersionRow(ThemeData theme) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          '当前 ${widget.info.currentVersion}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        Icon(Icons.arrow_forward, size: 16, color: theme.colorScheme.outline),
        Text(
          '最新 ${widget.info.latestVersion}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildNotes(ThemeData theme) {
    final notes = widget.info.notes;
    if (notes.isEmpty) {
      return Text(
        '本次发布未提供更新说明。',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }
    return SingleChildScrollView(child: MarkdownContent(content: notes));
  }

  List<Widget> _buildActions(ThemeData theme) {
    switch (_phase) {
      case _Phase.downloading:
        return [
          TextButton(onPressed: _cancelDownload, child: const Text('取消下载')),
        ];
      case _Phase.ready:
        return [
          TextButton(onPressed: _close, child: const Text('完成')),
          FilledButton(onPressed: _installAgain, child: const Text('重新安装')),
        ];
      case _Phase.failed:
        return [
          TextButton(onPressed: _close, child: const Text('关闭')),
          FilledButton(
            onPressed: widget.info.canInstallInApp ? _startDownload : null,
            child: const Text('重试'),
          ),
        ];
      case _Phase.idle:
        if (!widget.info.canInstallInApp) {
          return [
            TextButton(onPressed: _close, child: const Text('关闭')),
            FilledButton(
              onPressed: _copyDownloadUrl,
              child: const Text('复制下载链接'),
            ),
          ];
        }
        return [
          TextButton(
            onPressed: () => _close(skipped: true),
            child: const Text('稍后'),
          ),
          FilledButton(onPressed: _startDownload, child: const Text('立即更新')),
        ];
    }
  }
}
