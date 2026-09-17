import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_exception.dart';
import '../services/auth_service.dart';
import '../state/auth_store.dart';

/// 登录页：手机号验证码 + 用户名/邮箱账密（含 TOTP 二次验证）。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _totpController = TextEditingController();

  Timer? _timer;
  int _countdown = 0;
  bool _needTotp = false;
  bool _sendingCode = false;
  bool _showPassword = false;
  String? _phoneError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    final store = AuthStore.instance;
    if (!store.configLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => store.loadPublicConfig());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _totpController.dispose();
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
      setState(() {
        _countdown -= 1;
        if (_countdown <= 0) timer.cancel();
      });
    });
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!AuthService.isValidPhone(phone)) {
      setState(() => _phoneError = '请输入正确的手机号');
      return;
    }
    setState(() {
      _phoneError = null;
      _sendingCode = true;
    });
    try {
      final message = await AuthService.instance.sendPhoneCode(phone);
      if (!mounted) return;
      _startCountdown();
      _notify(message);
    } on ApiException catch (error) {
      _notify(error.message);
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _loginByCode() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (!AuthService.isValidPhone(phone)) {
      setState(() => _phoneError = '请输入正确的手机号');
      return;
    }
    if (!AuthService.isValidCode(code)) {
      _notify('验证码为 6 位数字');
      return;
    }
    setState(() => _phoneError = null);
    try {
      await AuthStore.instance.loginByCode(phoneNumber: phone, code: code);
    } on ApiException catch (error) {
      _notify(error.message);
    }
  }

  Future<void> _loginByPassword() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty) {
      setState(() => _passwordError = '请输入用户名或邮箱');
      return;
    }
    if (password.isEmpty) {
      setState(() => _passwordError = '请输入密码');
      return;
    }
    setState(() => _passwordError = null);
    try {
      await AuthStore.instance.loginByPassword(
        username: username,
        password: password,
        totpCode: _needTotp ? _totpController.text.trim() : null,
      );
    } on ApiException catch (error) {
      if (error.requiresTotp) {
        setState(() => _needTotp = true);
        _notify('该账号已启用二次验证，请输入动态验证码');
        return;
      }
      setState(() => _passwordError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AuthStore.instance;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final smsEnabled = store.publicConfig.smsEnabled;
        final tabs = <Widget>[
          if (smsEnabled) const Tab(text: '手机号验证码'),
          const Tab(text: '账号密码'),
        ];
        final views = <Widget>[
          if (smsEnabled) _buildPhoneTab(theme),
          _buildPasswordTab(theme),
        ];

        return DefaultTabController(
          key: ValueKey(smsEnabled),
          length: tabs.length,
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(theme),
                  TabBar(tabs: tabs),
                  Expanded(
                    child: TabBarView(children: views),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 20),
      child: Column(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 52,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text('Beancount-Trans', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '登录后查看审核待办与账本',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneTab(ThemeData theme) {
    final busy = AuthStore.instance.isBusy;
    return _FormBody(
      children: [
        TextField(
          controller: _phoneController,
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
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '验证码',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed:
                    (_countdown > 0 || _sendingCode || busy) ? null : _sendCode,
                child: Text(_countdown > 0 ? '$_countdown s' : '获取验证码'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: '登录',
          busy: busy,
          onPressed: busy ? null : _loginByCode,
        ),
        const SizedBox(height: 12),
        Text(
          '未注册的手机号将自动创建账号',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }

  Widget _buildPasswordTab(ThemeData theme) {
    final busy = AuthStore.instance.isBusy;
    return _FormBody(
      children: [
        TextField(
          controller: _usernameController,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '用户名或邮箱',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: '密码',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        if (_needTotp) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _totpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '动态验证码（TOTP）',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (_passwordError != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _passwordError!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _PrimaryButton(
          label: '登录',
          busy: busy,
          onPressed: busy ? null : _loginByPassword,
        ),
      ],
    );
  }
}

class _FormBody extends StatelessWidget {
  const _FormBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : Text(label),
      ),
    );
  }
}
