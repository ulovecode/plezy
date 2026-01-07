import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dpad_navigator.dart';

/// 通过弹出当前路由来处理返回键事件。
///
/// 可以选择传递一个 [result] 以返回到上一个路由。
///
/// 将此函数用作需要简单返回导航行为的 Focus 小部件的 `onKeyEvent` 回调：
///
/// ```dart
/// Focus(
///   onKeyEvent: (node, event) => handleBackKeyNavigation(context, event),
///   child: ...
/// )
/// ```
///
/// 带有结果值：
/// ```dart
/// Focus(
///   onKeyEvent: (node, event) => handleBackKeyNavigation(
///     context,
///     event,
///     result: _hasChanges,
///   ),
///   child: ...
/// )
/// ```
KeyEventResult handleBackKeyNavigation<T>(BuildContext context, KeyEvent event, {T? result}) {
  if (event is KeyDownEvent && event.logicalKey.isBackKey) {
    Navigator.pop(context, result);
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
