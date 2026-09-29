import 'package:flutter/material.dart';

import 'markdown_content.dart';

/// 单轮分享内容：一问一答（对齐 Web 端 `AssistantShareTurn`）。
class AssistantShareTurn {
  const AssistantShareTurn({
    required this.userMessage,
    required this.assistantContent,
  });

  final String userMessage;
  final String assistantContent;
}

/// 分享图最多包含的对话轮数（对齐 Web 端 `MAX_SHARE_TURNS`）。
const int kMaxShareTurns = 10;

/// 分享卡片固定宽度（对齐 Web 端 `AssistantShareCard.vue` 的 `640px`）。
const double kAssistantShareCardWidth = 640;

const Color _kTextPrimary = Color(0xFF303133);
const Color _kTextSecondary = Color(0xFF606266);
const Color _kTextTertiary = Color(0xFF909399);
const Color _kTextFaint = Color(0xFFC0C4CC);
const Color _kBorder = Color(0xFFEBEEF5);
const Color _kBorderStrong = Color(0xFFDCDFE6);
const Color _kAccent = Color(0xFF409EFF);

/// 分享长图卡片：结构、配色与文案对齐 Web 端 `AssistantShareCard.vue`。
///
/// 固定浅色且不使用系统字体缩放：分享图不随 App 深色主题变化，保证同一批对话
/// 在不同设备上输出一致。
class AssistantShareCard extends StatelessWidget {
  const AssistantShareCard({super.key, required this.turns});

  final List<AssistantShareTurn> turns;

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _kAccent,
        brightness: Brightness.light,
      ),
    );

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Theme(
        data: lightTheme,
        child: Material(
          color: Colors.white,
          child: SizedBox(
            width: kAssistantShareCardWidth,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  for (var i = 0; i < turns.length; i += 1) ...[
                    if (i > 0) _buildDivider(),
                    _buildTurn(i),
                  ],
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: _kAccent, width: 4),
          bottom: BorderSide(color: _kBorder),
        ),
      ),
      child: const Text(
        'Beancount-Trans',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _kTextPrimary,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorderStrong)),
      ),
    );
  }

  Widget _buildTurn(int index) {
    final turn = turns[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (turns.length > 1) ...[
          Text(
            '对话 ${index + 1}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
        ],
        _buildLabel('你的问题'),
        Text(
          turn.userMessage.trim(),
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: _kTextPrimary,
          ),
        ),
        const SizedBox(height: 16),
        _buildLabel('Copilot'),
        MarkdownContent(
          content: turn.assistantContent,
          selectable: false,
          baseStyle: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: _kTextPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _kTextTertiary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '隐私提示：本图可能包含个人账本信息，请勿随意分享给陌生人。',
            style: TextStyle(fontSize: 12, height: 1.5, color: _kTextTertiary),
          ),
          const SizedBox(height: 6),
          const Text(
            '以上内容由 AI 生成，仅供参考，请注意甄别。',
            style: TextStyle(fontSize: 12, height: 1.5, color: _kTextTertiary),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _shareDate(),
              style: const TextStyle(fontSize: 12, color: _kTextFaint),
            ),
          ),
        ],
      ),
    );
  }

  /// 日期文案与 Web 端 `toLocaleDateString('zh-CN', { year, month: 'long', day })` 一致。
  String _shareDate() {
    final now = DateTime.now();
    return '${now.year}年${now.month}月${now.day}日';
  }
}
