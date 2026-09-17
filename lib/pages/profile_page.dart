import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_exception.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../state/auth_store.dart';
import 'fava_page.dart';

/// 「我的」页：账号绑定信息、手机号绑定入口、Fava 报表入口、退出登录。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthStore.instance.refreshBindings();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openBindSheet() async {
    final bound = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BindPhoneSheet(),
    );
    if (bound == true && mounted) {
      _notify('手机号绑定成功');
    }
  }

  Future<void> _openFava() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FavaPage()),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后将清除本地登录状态，并停止当前 Fava 实例。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthStore.instance.logout();
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: AuthStore.instance,
      builder: (context, _) {
        final store = AuthStore.instance;
        final bindings = store.bindings ?? const UserBindings();
        final displayName = store.user?.displayName ?? '未登录';

        return Scaffold(
          appBar: AppBar(
            title: const Text('我的'),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _AccountHeader(
                  displayName: displayName,
                  subtitle: bindings.username.isNotEmpty
                      ? bindings.username
                      : bindings.email,
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  _ErrorBanner(message: _error!, onRetry: _load),
                  const SizedBox(height: 12),
                ],
                _SectionCard(
                  title: '账号绑定',
                  children: [
                    _InfoTile(
                      icon: Icons.person_outline,
                      label: '用户名',
                      value: bindings.username.isEmpty ? '未设置' : bindings.username,
                    ),
                    _InfoTile(
                      icon: Icons.mail_outline,
                      label: '邮箱',
                      value: bindings.email.isEmpty ? '未绑定' : bindings.email,
                    ),
                    _InfoTile(
                      icon: Icons.phone_iphone,
                      label: '手机号',
                      value: bindings.phoneNumber.isEmpty
                          ? '未绑定'
                          : bindings.phoneNumber,
                      trailing: bindings.phoneVerified
                          ? const _OkTag()
                          : const _WarnTag(text: '未验证'),
                    ),
                    _InfoTile(
                      icon: Icons.lock_outline,
                      label: '登录密码',
                      value: bindings.hasPassword ? '已设置' : '未设置',
                    ),
                  ],
                ),
                if (!bindings.phoneVerified) ...[
                  const SizedBox(height: 12),
                  _HintBanner(
                    text: store.publicConfig.smsEnabled
                        ? '未绑定手机号，可绑定后使用短信验证码登录。'
                        : '未绑定手机号。当前短信服务未启用，暂无法绑定。',
                    actionLabel:
                        store.publicConfig.smsEnabled ? '绑定手机号' : null,
                    onAction: store.publicConfig.smsEnabled
                        ? _openBindSheet
                        : null,
                  ),
                ],
                const SizedBox(height: 12),
                _SectionCard(
                  title: '报表',
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.open_in_new),
                      title: const Text('打开 Fava 报表'),
                      subtitle: Text(
                        store.publicConfig.favaDeployMode.isEmpty
                            ? '在应用内查看账本报表'
                            : '部署模式：${store.publicConfig.favaDeployMode}',
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openFava,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _confirmLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('退出登录'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.displayName, required this.subtitle});

  final String displayName;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            displayName.isEmpty ? '?' : displayName.characters.first.toUpperCase(),
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(displayName, style: theme.textTheme.titleMedium),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _OkTag extends StatelessWidget {
  const _OkTag();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Icon(Icons.verified, size: 16, color: theme.colorScheme.primary);
  }
}

class _WarnTag extends StatelessWidget {
  const _WarnTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.error),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = actionLabel;
    final action = label == null
        ? null
        : TextButton(onPressed: onAction, child: Text(label));

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// 手机号绑定弹层：手机号 → 发送验证码（60s 倒计时）→ 6 位验证码 → 绑定。
class _BindPhoneSheet extends StatefulWidget {
  const _BindPhoneSheet();

  @override
  State<_BindPhoneSheet> createState() => _BindPhoneSheetState();
}

class _BindPhoneSheetState extends State<_BindPhoneSheet> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();

  Timer? _timer;
  int _countdown = 0;
  bool _sending = false;
  bool _submitting = false;
  String? _phoneError;
  String? _codeError;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdown -= 1);
      if (_countdown <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (!AuthService.isValidPhone(phone)) {
      setState(() => _phoneError = '请输入 11 位有效手机号');
      return;
    }
    setState(() {
      _phoneError = null;
      _sending = true;
    });
    try {
      final message = await AuthService.instance.sendPhoneCode(phone);
      if (!mounted) return;
      _startCountdown();
      _notify(message);
    } on ApiException catch (error) {
      if (mounted) setState(() => _phoneError = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (!AuthService.isValidPhone(phone)) {
      setState(() => _phoneError = '请输入 11 位有效手机号');
      return;
    }
    if (!AuthService.isValidCode(code)) {
      setState(() => _codeError = '请输入 6 位数字验证码');
      return;
    }
    setState(() {
      _phoneError = null;
      _codeError = null;
      _submitting = true;
    });
    try {
      await AuthStore.instance.bindPhone(phoneNumber: phone, code: code);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _codeError = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final canSend = !_sending && _countdown == 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('绑定手机号', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '绑定后可使用短信验证码登录。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '手机号',
              prefixText: '+86 ',
              counterText: '',
              border: const OutlineInputBorder(),
              errorText: _phoneError,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: '验证码',
                    counterText: '',
                    border: const OutlineInputBorder(),
                    errorText: _codeError,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: canSend ? _sendCode : null,
                  child: Text(
                    _countdown > 0 ? '${_countdown}s' : '发送验证码',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确认绑定'),
          ),
        ],
      ),
    );
  }
}
