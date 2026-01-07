import 'dart:io' show Platform;
import 'package:flutter/material.dart' show Offset;
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:macos_window_utils/macos/ns_window_button_type.dart';
import 'fullscreen_window_delegate.dart';

/// 用于管理 macOS 标题栏配置的服务
class MacOSTitlebarService {
  // 使用自定义工具栏时的标准按钮 Y 轴位置
  static const double _customButtonY = 21.0;

  /// 初始化自定义标题栏设置 (带有工具栏的透明标题栏)
  /// 此配置会自动原生处理全屏模式
  static Future<void> setupCustomTitlebar() async {
    if (!Platform.isMacOS) return;

    // 启用窗口委托以使用呈现选项和全屏回调
    await WindowManipulator.initialize(enableWindowDelegate: true);

    // 注册自定义委托以处理全屏转换
    final delegate = FullscreenWindowDelegate();
    WindowManipulator.addNSWindowDelegate(delegate);

    // 使标题栏透明但保持其功能
    await WindowManipulator.makeTitlebarTransparent();
    await WindowManipulator.hideTitle();
    await WindowManipulator.enableFullSizeContentView();

    // 添加工具栏以在普通模式下为红绿灯按钮腾出空间
    await WindowManipulator.addToolbar();

    // 设置普通模式下的自定义红绿灯按钮位置
    await _setCustomButtonPositions();

    // 配置全屏呈现以自动隐藏工具栏和菜单栏
    // 这告诉 macOS 在进入全屏时自动隐藏工具栏
    final presentationOptions = NSAppPresentationOptions.from({
      NSAppPresentationOption.fullScreen,
      NSAppPresentationOption.autoHideToolbar,
      NSAppPresentationOption.autoHideMenuBar,
      NSAppPresentationOption.autoHideDock,
    });
    presentationOptions.applyAsFullScreenPresentationOptions();
  }

  /// 将红绿灯按钮设置为自定义位置 (带有工具栏偏移量)
  static Future<void> _setCustomButtonPositions() async {
    await WindowManipulator.overrideStandardWindowButtonPosition(
      buttonType: NSWindowButtonType.closeButton,
      offset: const Offset(20, _customButtonY),
    );
    await WindowManipulator.overrideStandardWindowButtonPosition(
      buttonType: NSWindowButtonType.miniaturizeButton,
      offset: const Offset(40, _customButtonY),
    );
    await WindowManipulator.overrideStandardWindowButtonPosition(
      buttonType: NSWindowButtonType.zoomButton,
      offset: const Offset(60, _customButtonY),
    );
  }
}
