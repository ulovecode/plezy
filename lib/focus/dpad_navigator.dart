import 'package:flutter/services.dart';

/// KeyEvent 的扩展，用于常见的事件类型检查。
extension KeyEventActionable on KeyEvent {
  /// 此事件是否应触发操作（KeyDownEvent 或 KeyRepeatEvent）。
  /// 使用此属性可以在按键处理器中尽早过滤掉 KeyUpEvent。
  bool get isActionable => this is KeyDownEvent || this is KeyRepeatEvent;
}

/// 键盘按键分类的共享集合。
final _dpadDirectionKeys = {
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
};

final _selectKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

final _backKeys = {
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.goBack,
  LogicalKeyboardKey.browserBack,
  LogicalKeyboardKey.gameButtonB,
};

final _contextMenuKeys = {LogicalKeyboardKey.contextMenu, LogicalKeyboardKey.gameButtonX};

/// 用于检查 D-pad 相关按键的扩展方法。
extension DpadKeyExtension on LogicalKeyboardKey {
  /// 此按键是否为 D-pad 方向键。
  bool get isDpadDirection => _dpadDirectionKeys.contains(this);

  /// 此按键是否为选择/激活键。
  bool get isSelectKey => _selectKeys.contains(this);

  /// 此按键是否为返回/取消键。
  bool get isBackKey => _backKeys.contains(this);

  /// 此按键是否为上下文菜单键。
  bool get isContextMenuKey => _contextMenuKeys.contains(this);

  /// 此按键是否向左移动焦点。
  bool get isLeftKey => this == LogicalKeyboardKey.arrowLeft;

  /// 此按键是否向右移动焦点。
  bool get isRightKey => this == LogicalKeyboardKey.arrowRight;

  /// 此按键是否向上移动焦点。
  bool get isUpKey => this == LogicalKeyboardKey.arrowUp;

  /// 此按键是否向下移动焦点。
  bool get isDownKey => this == LogicalKeyboardKey.arrowDown;
}
