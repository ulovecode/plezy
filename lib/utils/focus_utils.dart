import 'package:flutter/widgets.dart';

/// 常用焦点操作的工具类
class FocusUtils {
  FocusUtils._();

  /// 在当前帧构建完成后请求 FocusNode 获得焦点。
  /// 在请求焦点之前，安全地检查 State 是否仍处于挂载（mounted）状态。
  ///
  /// 用法：
  /// ```dart
  /// FocusUtils.requestFocusAfterBuild(this, _focusNode);
  /// ```
  static void requestFocusAfterBuild(State state, FocusNode focusNode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.mounted) {
        focusNode.requestFocus();
      }
    });
  }

  /// 在当前帧构建完成后执行回调，并进行挂载状态检查。
  /// 只有当 State 仍处于挂载状态时，回调才会执行。
  ///
  /// 用法：
  /// ```dart
  /// FocusUtils.afterBuildIfMounted(this, () {
  ///   // 执行某些操作
  /// });
  /// ```
  static void afterBuildIfMounted(State state, VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.mounted) {
        callback();
      }
    });
  }

  /// 在当前帧构建完成后执行回调，不进行挂载状态检查。
  /// 当您不需要挂载检查或自行管理挂载状态时使用。
  ///
  /// 用法：
  /// ```dart
  /// FocusUtils.afterBuild(() {
  ///   // 执行某些操作
  /// });
  /// ```
  static void afterBuild(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      callback();
    });
  }
}
