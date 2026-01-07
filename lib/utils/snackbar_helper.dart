import 'package:flutter/material.dart';

/// 应用程序中可用的 Snackbar 类型
enum SnackBarType {
  /// 标准信息 Snackbar
  info,

  /// 成功 Snackbar（绿色背景）
  success,

  /// 错误 Snackbar（红色背景）
  error,
}

/// 用于在整个应用程序中显示 Snackbar 的工具函数

/// 显示指定类型的 Snackbar
///
/// [context] 构建上下文
/// [message] 要显示的消息
/// [type] Snackbar 类型 (info, success, error)
/// [duration] 可选的持续时间覆盖
void showSnackBar(BuildContext context, String message, {SnackBarType type = SnackBarType.info, Duration? duration}) {
  if (!context.mounted) return;

  final (backgroundColor, defaultDuration) = switch (type) {
    SnackBarType.info => (null, const Duration(seconds: 3)),
    SnackBarType.success => (Colors.green, const Duration(seconds: 3)),
    SnackBarType.error => (Colors.red, const Duration(seconds: 4)),
  };

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: backgroundColor, duration: duration ?? defaultDuration),
  );
}

/// 显示标准带消息的 Snackbar
///
/// [context] 构建上下文
/// [message] 要显示的消息
/// [duration] 可选持续时间，默认为 3 秒
void showAppSnackBar(BuildContext context, String message, {Duration? duration}) {
  showSnackBar(context, message, type: SnackBarType.info, duration: duration);
}

/// 显示带消息的错误 Snackbar
///
/// [context] 构建上下文
/// [message] 要显示的错误消息
void showErrorSnackBar(BuildContext context, String message) {
  showSnackBar(context, message, type: SnackBarType.error);
}

/// 显示带消息的成功 Snackbar
///
/// [context] 构建上下文
/// [message] 要显示的成功消息
void showSuccessSnackBar(BuildContext context, String message) {
  showSnackBar(context, message, type: SnackBarType.success);
}
