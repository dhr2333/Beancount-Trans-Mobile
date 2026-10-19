import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 全屏右滑打开抽屉的手势层。
///
/// 手势层位于 [child] 之上，因此优先于正文的文字选择手势；指针按下时会先做
/// 命中测试：若落在横向可滚动区域（Markdown 表格、代码块等），本次手势不加入
/// 竞争，由内部横向滚动接管；其余区域按系统默认阈值识别右滑并回调 [onOpen]。
class DrawerSwipeLayer extends StatelessWidget {
  const DrawerSwipeLayer({
    super.key,
    required this.onOpen,
    required this.child,
  });

  /// 识别到右滑时调用，通常用于打开抽屉。
  final VoidCallback onOpen;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: <Type, GestureRecognizerFactory>{
              _DrawerOpenDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _DrawerOpenDragRecognizer
                  >(
                    () => _DrawerOpenDragRecognizer(
                      debugOwner: this,
                      onOpen: onOpen,
                    ),
                    (_) {},
                  ),
            },
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

/// 识别向右的横向拖动；左滑不触发，避免误开抽屉。
class _DrawerOpenDragRecognizer extends HorizontalDragGestureRecognizer {
  _DrawerOpenDragRecognizer({super.debugOwner, required this.onOpen}) {
    onStart = (_) {
      _dragDx = 0;
      _opened = false;
    };
    onUpdate = (details) {
      _dragDx += details.delta.dx;
      if (_opened || _dragDx <= 0) return;
      _opened = true;
      onOpen();
    };
  }

  final VoidCallback onOpen;
  bool _opened = false;
  double _dragDx = 0;

  @override
  void addPointer(PointerDownEvent event) {
    _opened = false;
    _dragDx = 0;
    // 落在横向可滚动区域时让位给表格/代码块的横向滚动。
    if (_isOverHorizontalScrollable(event)) return;
    super.addPointer(event);
  }

  /// 判断按下点是否落在横向可滚动区域上。
  ///
  /// 不走命中测试路径：表格边框/单元格间隙处可能命中不到 viewport 本身，
  /// 这里直接遍历渲染树，用横向 viewport 的全局矩形判断，覆盖完整表格区域。
  bool _isOverHorizontalScrollable(PointerDownEvent event) {
    final position = event.position;
    var found = false;

    void visit(RenderObject node) {
      if (found) return;
      if (node is RenderOffstage && node.offstage) return;
      final target = node;
      if (target is RenderAbstractViewport && _isHorizontal(target)) {
        final box = target as RenderBox;
        if (box.hasSize) {
          final rect = box.localToGlobal(Offset.zero) & box.size;
          if (rect.contains(position)) {
            found = true;
            return;
          }
        }
      }
      node.visitChildren(visit);
    }

    for (final view in RendererBinding.instance.renderViews) {
      if (view.flutterView.viewId != event.viewId) continue;
      view.visitChildren(visit);
    }
    return found;
  }

  bool _isHorizontal(RenderAbstractViewport viewport) {
    try {
      final dynamic target = viewport;
      final AxisDirection direction = target.axisDirection as AxisDirection;
      return axisDirectionToAxis(direction) == Axis.horizontal;
    } catch (_) {
      // 个别 viewport 未暴露 axisDirection，忽略即可。
      return false;
    }
  }
}
