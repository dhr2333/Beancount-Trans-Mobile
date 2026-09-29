import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/alias_input.dart';
import '../core/api_exception.dart';
import '../state/shared_ledger_store.dart';

/// 弹出「添加共享账本」底部表单，返回是否添加成功。
Future<bool?> showAddSharedLedgerSheet(
  BuildContext context, {
  String? initialToken,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddSharedLedgerSheet(initialToken: initialToken),
  );
}

/// 添加共享账本弹层：令牌（必填）+ 可选多别名，可复用（可带预填令牌）。
class _AddSharedLedgerSheet extends StatefulWidget {
  const _AddSharedLedgerSheet({this.initialToken});

  final String? initialToken;

  @override
  State<_AddSharedLedgerSheet> createState() => _AddSharedLedgerSheetState();
}

class _AddSharedLedgerSheetState extends State<_AddSharedLedgerSheet> {
  late final TextEditingController _token = TextEditingController(
    text: widget.initialToken ?? '',
  );
  final TextEditingController _aliases = TextEditingController();

  bool _submitting = false;
  String? _tokenError;
  String? _aliasError;
  String? _submitError;

  @override
  void dispose() {
    _token.dispose();
    _aliases.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _notify('剪贴板为空');
      return;
    }
    setState(() {
      _token.text = text;
      _tokenError = null;
    });
  }

  Future<void> _submit() async {
    final token = _token.text.trim();
    if (token.isEmpty) {
      setState(() => _tokenError = '请粘贴或输入访问令牌');
      return;
    }
    final aliases = parseAliases(_aliases.text);
    for (final alias in aliases) {
      final error = aliasValidationError(alias);
      if (error != null) {
        setState(() => _aliasError = error);
        return;
      }
    }
    setState(() {
      _tokenError = null;
      _aliasError = null;
      _submitError = null;
      _submitting = true;
    });
    try {
      await SharedLedgerStore.instance.bind(token: token, aliases: aliases);
      if (!mounted) return;
      _notify('共享账本已添加');
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _submitError = error.message);
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

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('添加共享账本', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '别名可留空，也可填多个（用逗号、顿号或空格分隔）；'
              'Copilot 命中任意一个别名即可识别该账本，留空时使用来源用户名。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _token,
              maxLines: 3,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '访问令牌',
                hintText: '粘贴 bct_ 开头的令牌',
                border: const OutlineInputBorder(),
                errorText: _tokenError,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _submitting ? null : _pasteFromClipboard,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('从剪贴板粘贴'),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _aliases,
              decoration: InputDecoration(
                labelText: '别名（可选，可多个）',
                hintText: '多个别名用逗号分隔，例如：老婆的账本、老婆',
                border: const OutlineInputBorder(),
                errorText: _aliasError,
              ),
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 10),
              Text(
                _submitError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
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
                  : const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹出「编辑别名」底部表单，返回是否保存成功。
Future<bool?> showEditSharedLedgerAliasesSheet(
  BuildContext context, {
  required int bindingId,
  required List<String> aliases,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _EditSharedLedgerAliasesSheet(bindingId: bindingId, aliases: aliases),
  );
}

/// 编辑共享账本别名弹层：预填现有别名，保存时整体覆盖。
class _EditSharedLedgerAliasesSheet extends StatefulWidget {
  const _EditSharedLedgerAliasesSheet({
    required this.bindingId,
    required this.aliases,
  });

  final int bindingId;
  final List<String> aliases;

  @override
  State<_EditSharedLedgerAliasesSheet> createState() =>
      _EditSharedLedgerAliasesSheetState();
}

class _EditSharedLedgerAliasesSheetState
    extends State<_EditSharedLedgerAliasesSheet> {
  late final TextEditingController _aliases = TextEditingController(
    text: widget.aliases.join('、'),
  );

  bool _submitting = false;
  String? _aliasError;
  String? _submitError;

  @override
  void dispose() {
    _aliases.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final aliases = parseAliases(_aliases.text);
    for (final alias in aliases) {
      final error = aliasValidationError(alias);
      if (error != null) {
        setState(() => _aliasError = error);
        return;
      }
    }
    setState(() {
      _aliasError = null;
      _submitError = null;
      _submitting = true;
    });
    try {
      await SharedLedgerStore.instance.updateAliases(
        id: widget.bindingId,
        aliases: aliases,
      );
      if (!mounted) return;
      _notify('别名已更新');
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _submitError = error.message);
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

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('编辑别名', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '别名可留空，也可填多个（用逗号、顿号或空格分隔）；'
              'Copilot 命中任意一个别名即可识别该账本，留空时使用来源用户名。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _aliases,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '别名（可选，可多个）',
                hintText: '多个别名用逗号分隔，例如：老婆的账本、老婆',
                border: const OutlineInputBorder(),
                errorText: _aliasError,
              ),
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 10),
              Text(
                _submitError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
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
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
