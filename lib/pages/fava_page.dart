import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/api_exception.dart';
import '../services/fava_service.dart';

/// Fava 报表页（全屏路由）：内嵌 WebView，解析实例地址后加载。
///
/// 入口：「我的」页的「打开 Fava 报表」、Copilot 查询卡片上的 `fava_path`。
class FavaPage extends StatefulWidget {
  const FavaPage({super.key, this.relativePath});

  /// 可选深链相对路径（来自 Copilot 的 `fava_path`）。
  final String? relativePath;

  @override
  State<FavaPage> createState() => _FavaPageState();
}

class _FavaPageState extends State<FavaPage> {
  WebViewController? _controller;
  String? _error;
  String? _allowedHost;
  double _progress = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = 0;
    });

    try {
      final prefix = await FavaService.instance.resolveFavaUrl();
      final relative = widget.relativePath ?? '';
      final target =
          relative.isEmpty ? prefix : FavaService.join(prefix, relative);
      final uri = Uri.parse(target);
      _allowedHost = uri.host;

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (value) {
              if (mounted) setState(() => _progress = value / 100);
            },
            onPageFinished: (_) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _progress = 1;
                });
              }
            },
            onWebResourceError: (error) {
              if (!mounted) return;
              if (error.isForMainFrame == false) return;
              setState(() {
                _loading = false;
                _error = error.description.isEmpty
                    ? '页面加载失败'
                    : error.description;
              });
            },
            onNavigationRequest: _onNavigationRequest,
          ),
        )
        ..loadRequest(uri);

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '打开 Fava 失败，请稍后重试';
        });
      }
    }
  }

  /// 仅允许在本域内导航；外链一律拦截（不引入额外依赖打开系统浏览器）。
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    if (isHttp && (_allowedHost == null || uri.host == _allowedHost)) {
      return NavigationDecision.navigate;
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _notifyExternalBlocked(request.url));
    return NavigationDecision.prevent;
  }

  void _notifyExternalBlocked(String url) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已拦截外部链接：$url'),
          action: SnackBarAction(
            label: '复制链接',
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
          ),
        ),
      );
  }

  Future<void> _handleBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fava 报表'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _loading
                  ? null
                  : () => _controller?.reload() ?? _resolve(),
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _loading || _progress < 1
                ? LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                    minHeight: 2,
                  )
                : const SizedBox(height: 2),
          ),
        ),
        body: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 44, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text('无法打开 Fava', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _resolve,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return WebViewWidget(controller: controller);
  }
}
