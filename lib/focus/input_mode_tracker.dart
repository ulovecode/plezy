import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_detector.dart';
import '../services/gamepad_service.dart';

/// 跟踪用户是通过键盘/D-pad 还是通过指针（鼠标/触摸）进行导航。
///
/// 焦点效果应仅在键盘导航期间显示。
enum InputMode { keyboard, pointer }

/// 向后代小部件提供输入模式跟踪。
///
/// 使用此小部件包装你的应用程序以启用输入模式检测：
/// ```dart
/// InputModeTracker(
///   child: MaterialApp(...),
/// )
/// ```
///
/// 然后在可聚焦的小部件中检查模式：
/// ```dart
/// final showFocus = _isFocused && InputModeTracker.isKeyboardMode(context);
/// ```
class InputModeTracker extends StatefulWidget {
  final Widget child;

  const InputModeTracker({super.key, required this.child});

  /// 获取当前的输入模式。
  static InputMode of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<_InputModeProvider>();
    return provider?.mode ?? InputMode.pointer;
  }

  /// 检查是否处于键盘模式的便捷方法。
  static bool isKeyboardMode(BuildContext context) {
    return of(context) == InputMode.keyboard;
  }

  @override
  State<InputModeTracker> createState() => _InputModeTrackerState();
}

class _InputModeTrackerState extends State<InputModeTracker> {
  // 在 Android TV 上默认为键盘模式，其他地方默认为指针模式
  InputMode _mode = TvDetectionService.isTVSync() ? InputMode.keyboard : InputMode.pointer;

  @override
  void initState() {
    super.initState();
    // 根据起始模式初始化焦点高亮策略
    _updateFocusHighlightStrategy(_mode);
    // 全局监听硬件键盘事件
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    // 注册游戏手柄输入的回调以切换到键盘模式
    GamepadService.onGamepadInput = () => _setMode(InputMode.keyboard);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    GamepadService.onGamepadInput = null;
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    // 仅在按下按键时切换到键盘模式（不包括重复或释放）
    if (event is KeyDownEvent) {
      _setMode(InputMode.keyboard);
    }
    // 返回 false 以让事件继续传播
    return false;
  }

  void _setMode(InputMode mode) {
    if (_mode != mode) {
      setState(() => _mode = mode);
    }
    _updateFocusHighlightStrategy(mode);
  }

  // 保持 Material 焦点高亮与我们的输入模式同步，
  // 以便键盘/游戏手柄导航能立即显示焦点，而无需等待真实的按键操作。
  void _updateFocusHighlightStrategy(InputMode mode) {
    final desiredStrategy = mode == InputMode.keyboard
        ? FocusHighlightStrategy.alwaysTraditional
        : FocusHighlightStrategy.automatic;

    if (FocusManager.instance.highlightStrategy != desiredStrategy) {
      FocusManager.instance.highlightStrategy = desiredStrategy;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 在 Android TV 上，不要从指针事件切换到指针模式，
    // 因为 D-pad 可能会生成合成的指针事件，这会错误地触发指针模式并显示光标，
    // 而不是 D-pad 焦点导航。
    if (TvDetectionService.isTVSync()) {
      return _InputModeProvider(mode: _mode, child: widget.child);
    }

    return Listener(
      // 在鼠标活动时切换到指针模式
      onPointerDown: (_) => _setMode(InputMode.pointer),
      onPointerHover: (_) => _setMode(InputMode.pointer),
      behavior: HitTestBehavior.translucent,
      child: _InputModeProvider(mode: _mode, child: widget.child),
    );
  }
}

/// 提供当前输入模式的 InheritedWidget。
class _InputModeProvider extends InheritedWidget {
  final InputMode mode;

  const _InputModeProvider({required this.mode, required super.child});

  @override
  bool updateShouldNotify(_InputModeProvider oldWidget) {
    return mode != oldWidget.mode;
  }
}
