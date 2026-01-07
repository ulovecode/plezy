import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';

import '../utils/app_logger.dart';

/// 将游戏手柄输入桥接到 Flutter 焦点导航系统的服务。
///
/// 监听来自 `gamepads` 包的手柄事件，并将其转换为焦点导航操作和键事件，
/// 与现有的键盘导航系统集成。
class GamepadService {
  static GamepadService? _instance;
  StreamSubscription<GamepadEvent>? _subscription;

  /// 将 InputModeTracker 切换到键盘模式的回调。
  /// 由 InputModeTracker 在初始化时设置。
  static VoidCallback? onGamepadInput;

  /// L1 肩键按下的回调 (上一个标签页)。
  /// 带有标签页的屏幕可以监听此回调。
  static VoidCallback? onL1Pressed;

  /// R1 肩键按下的回调 (下一个标签页)。
  /// 带有标签页的屏幕可以监听此回调。
  static VoidCallback? onR1Pressed;

  // 模拟摇杆的死区 (0.0 到 1.0)
  static const double _stickDeadzone = 0.5;

  // 跟踪方向键 (D-pad) 状态以避免重复的导航事件
  bool _dpadUp = false;
  bool _dpadDown = false;
  bool _dpadLeft = false;
  bool _dpadRight = false;

  // 跟踪摇杆状态以避免重复的导航事件
  bool _leftStickUp = false;
  bool _leftStickDown = false;
  bool _leftStickLeft = false;
  bool _leftStickRight = false;

  // 跟踪按钮状态以防止长按按钮产生重复事件
  final Set<String> _pressedButtons = {};

  GamepadService._();

  /// 获取单例实例。
  static GamepadService get instance {
    _instance ??= GamepadService._();
    return _instance!;
  }

  /// 开始监听手柄事件。
  /// 仅在桌面平台 (macOS, Windows, Linux) 上激活。
  void start() async {
    // 仅在桌面平台启用
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;

    appLogger.i('GamepadService: 正在 ${Platform.operatingSystem} 上启动');

    // 列出已连接的手柄
    try {
      final gamepads = await Gamepads.list();
      appLogger.i('GamepadService: 找到 ${gamepads.length} 个手柄');
      for (final gamepad in gamepads) {
        appLogger.i('  - ${gamepad.name} (id: ${gamepad.id})');
      }
    } catch (e) {
      appLogger.e('GamepadService: 列出手柄时出错', error: e);
    }

    _subscription?.cancel();
    _subscription = Gamepads.events.listen(
      _handleGamepadEvent,
      onError: (e) => appLogger.e('GamepadService: 流错误', error: e),
    );
    appLogger.i('GamepadService: 正在监听手柄事件');
  }

  /// 停止监听手柄事件。
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _handleGamepadEvent(GamepadEvent event) {
    final key = event.key.toLowerCase();
    final value = event.value;

    // 在任何显著的手柄输入时切换到键盘模式
    if (value.abs() > 0.3) {
      onGamepadInput?.call();
      _setTraditionalFocusHighlight();
      _scheduleFrameIfIdle();
    }

    // 处理方向键 (macOS 上报告为轴)
    if (_isDpadYAxis(key)) {
      _handleDpadY(value);
      return;
    }
    if (_isDpadXAxis(key)) {
      _handleDpadX(value);
      return;
    }

    // 处理功能按钮
    final isPressed = value > 0.5;
    final wasPressed = _pressedButtons.contains(key);

    if (isPressed && !wasPressed) {
      _pressedButtons.add(key);

      if (_isButtonA(key)) {
        // 使用 enter 而不是 gameButtonA，以便它能与 Flutter 的内置组件
        // (按钮、列表项等) 配合使用，这些组件会监听 enter 键
        _simulateKeyPress(LogicalKeyboardKey.enter);
      } else if (_isButtonB(key)) {
        // 使用 escape 而不是 gameButtonB，以便它能与 Flutter 的内置组件
        // (底部菜单、对话框、菜单) 配合使用，这些组件通常只监听 escape 键
        _simulateKeyPress(LogicalKeyboardKey.escape);
      } else if (_isButtonX(key)) {
        _simulateKeyPress(LogicalKeyboardKey.gameButtonX);
      } else if (_isL1(key)) {
        onL1Pressed?.call();
      } else if (_isR1(key)) {
        onR1Pressed?.call();
      }
    } else if (!isPressed && wasPressed) {
      _pressedButtons.remove(key);
    }

    // 处理左模拟摇杆
    if (_isLeftStickY(key)) {
      _handleLeftStickY(value);
      return;
    }
    if (_isLeftStickX(key)) {
      _handleLeftStickX(value);
      return;
    }
  }

  void _moveFocus(TraversalDirection direction) {
    // 将方向转换为方向键并模拟按键按下
    // 这允许像 HubSection 这样拦截键事件的组件来处理导航
    final logicalKey = _directionToKey(direction);
    _simulateKeyPress(logicalKey);
  }

  LogicalKeyboardKey _directionToKey(TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.up:
        return LogicalKeyboardKey.arrowUp;
      case TraversalDirection.down:
        return LogicalKeyboardKey.arrowDown;
      case TraversalDirection.left:
        return LogicalKeyboardKey.arrowLeft;
      case TraversalDirection.right:
        return LogicalKeyboardKey.arrowRight;
    }
  }

  void _simulateKeyPress(LogicalKeyboardKey logicalKey) {
    // 在下一帧调度以确保我们在主线程上
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final focusNode = FocusManager.instance.primaryFocus;
      if (focusNode == null) return;

      // 创建一个合成的按键按下事件
      final keyDownEvent = KeyDownEvent(
        physicalKey: _getPhysicalKey(logicalKey),
        logicalKey: logicalKey,
        timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
      );

      // 通过向上遍历焦点树并调用每个节点的 onKeyEvent 处理程序来分发到焦点系统
      FocusNode? node = focusNode;
      KeyEventResult result = KeyEventResult.ignored;

      while (node != null && result != KeyEventResult.handled) {
        // Focus 组件将其处理程序存储在 onKeyEvent 中
        if (node.onKeyEvent != null) {
          result = node.onKeyEvent!(node, keyDownEvent);
        }
        node = node.parent;
      }

      // 发送按键弹起事件
      final keyUpEvent = KeyUpEvent(
        physicalKey: _getPhysicalKey(logicalKey),
        logicalKey: logicalKey,
        timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
      );

      node = focusNode;
      while (node != null) {
        if (node.onKeyEvent != null) {
          final upResult = node.onKeyEvent!(node, keyUpEvent);
          if (upResult == KeyEventResult.handled) break;
        }
        node = node.parent;
      }
    });
  }

  PhysicalKeyboardKey _getPhysicalKey(LogicalKeyboardKey logicalKey) {
    if (logicalKey == LogicalKeyboardKey.gameButtonA) {
      return PhysicalKeyboardKey.gameButtonA;
    } else if (logicalKey == LogicalKeyboardKey.gameButtonB) {
      return PhysicalKeyboardKey.gameButtonB;
    } else if (logicalKey == LogicalKeyboardKey.gameButtonX) {
      return PhysicalKeyboardKey.gameButtonX;
    } else if (logicalKey == LogicalKeyboardKey.arrowUp) {
      return PhysicalKeyboardKey.arrowUp;
    } else if (logicalKey == LogicalKeyboardKey.arrowDown) {
      return PhysicalKeyboardKey.arrowDown;
    } else if (logicalKey == LogicalKeyboardKey.arrowLeft) {
      return PhysicalKeyboardKey.arrowLeft;
    } else if (logicalKey == LogicalKeyboardKey.arrowRight) {
      return PhysicalKeyboardKey.arrowRight;
    } else if (logicalKey == LogicalKeyboardKey.escape) {
      return PhysicalKeyboardKey.escape;
    }
    return PhysicalKeyboardKey.enter;
  }

  // macOS DualSense 按键匹配
  // 方向键报告为轴：dpad - xaxis, dpad - yaxis
  bool _isDpadYAxis(String key) => key == 'dpad - yaxis';
  bool _isDpadXAxis(String key) => key == 'dpad - xaxis';

  // 功能按钮 - macOS 为 PlayStation 控制器使用 SF Symbol 名称
  bool _isButtonA(String key) => key == 'xmark.circle'; // Cross/X 按钮 (底部)
  bool _isButtonB(String key) => key == 'circle.circle'; // Circle/O 按钮 (右侧)
  bool _isButtonX(String key) => key == 'square.circle'; // Square 按钮 (左侧)

  // 模拟摇杆
  bool _isLeftStickX(String key) => key == 'l.joystick - xaxis';
  bool _isLeftStickY(String key) => key == 'l.joystick - yaxis';

  // 肩键按钮
  bool _isL1(String key) => key == 'l1.rectangle.roundedbottom';
  bool _isR1(String key) => key == 'r1.rectangle.roundedbottom';

  // 方向键 Y 轴：-1 = 下 (手柄上视觉为上)，1 = 上 (视觉为下)
  // 反转是因为 macOS 报告的与预期相反
  void _handleDpadY(double value) {
    if (value < -0.5 && !_dpadDown) {
      _dpadDown = true;
      _dpadUp = false;
      _moveFocus(TraversalDirection.down);
    } else if (value > 0.5 && !_dpadUp) {
      _dpadUp = true;
      _dpadDown = false;
      _moveFocus(TraversalDirection.up);
    } else if (value == 0) {
      _dpadUp = false;
      _dpadDown = false;
    }
  }

  // 方向键 X 轴：-1 = 左，1 = 右，0 = 释放
  void _handleDpadX(double value) {
    if (value < -0.5 && !_dpadLeft) {
      _dpadLeft = true;
      _dpadRight = false;
      _moveFocus(TraversalDirection.left);
    } else if (value > 0.5 && !_dpadRight) {
      _dpadRight = true;
      _dpadLeft = false;
      _moveFocus(TraversalDirection.right);
    } else if (value == 0) {
      _dpadLeft = false;
      _dpadRight = false;
    }
  }

  // 左摇杆 Y 轴 - 与方向键一样反转
  void _handleLeftStickY(double value) {
    if (value < -_stickDeadzone && !_leftStickDown) {
      _leftStickDown = true;
      _leftStickUp = false;
      _moveFocus(TraversalDirection.down);
    } else if (value > _stickDeadzone && !_leftStickUp) {
      _leftStickUp = true;
      _leftStickDown = false;
      _moveFocus(TraversalDirection.up);
    } else if (value.abs() <= _stickDeadzone) {
      _leftStickUp = false;
      _leftStickDown = false;
    }
  }

  void _handleLeftStickX(double value) {
    if (value < -_stickDeadzone && !_leftStickLeft) {
      _leftStickLeft = true;
      _leftStickRight = false;
      _moveFocus(TraversalDirection.left);
    } else if (value > _stickDeadzone && !_leftStickRight) {
      _leftStickRight = true;
      _leftStickLeft = false;
      _moveFocus(TraversalDirection.right);
    } else if (value.abs() <= _stickDeadzone) {
      _leftStickLeft = false;
      _leftStickRight = false;
    }
  }

  // 确保 Material 在通过手柄导航时使用传统的 (键盘) 焦点高亮。
  // 我们下面分发的合成键事件不会通过平台按键管道，因此 Flutter 不会自动切换高亮模式。
  void _setTraditionalFocusHighlight() {
    if (FocusManager.instance.highlightStrategy != FocusHighlightStrategy.alwaysTraditional) {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    }
  }

  // 在手柄输入时，如果引擎处于空闲状态，则强制执行一帧，以便焦点视觉效果立即更新
  // (桌面端在没有鼠标/键盘活动的情况下可能不会唤醒)。
  void _scheduleFrameIfIdle() {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.idle) {
      scheduler.scheduleFrame();
    }
  }
}
