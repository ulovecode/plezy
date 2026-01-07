import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:macos_window_utils/macos/ns_window_delegate.dart';
import 'package:macos_window_utils/macos/ns_window_button_type.dart';
import 'package:flutter/material.dart' show Offset;
import 'fullscreen_state_manager.dart';

/// 自定义窗口委托，在全屏转换期间管理标题栏配置
class FullscreenWindowDelegate extends NSWindowDelegate {
  static const double _customButtonY = 21.0;

  @override
  void windowWillEnterFullScreen() {
    // 通知全局状态管理器
    FullscreenStateManager().setFullscreen(true);

    // 在进入全屏之前移除工具栏并恢复默认标题栏
    _prepareForFullscreen();
  }

  @override
  void windowWillExitFullScreen() {
    // 立即隐藏标题并设为透明 (在转换前操作是安全的)
    WindowManipulator.hideTitle();
    WindowManipulator.makeTitlebarTransparent();
  }

  @override
  void windowDidExitFullScreen() {
    // 通知全局状态管理器
    FullscreenStateManager().setFullscreen(false);

    // 转换完成后添加工具栏并重新定位红绿灯按钮
    WindowManipulator.addToolbar();

    // 恢复自定义红绿灯按钮位置
    WindowManipulator.overrideStandardWindowButtonPosition(
      buttonType: NSWindowButtonType.closeButton,
      offset: const Offset(20, _customButtonY),
    );
    WindowManipulator.overrideStandardWindowButtonPosition(
      buttonType: NSWindowButtonType.miniaturizeButton,
      offset: const Offset(40, _customButtonY),
    );
    WindowManipulator.overrideStandardWindowButtonPosition(
      buttonType: NSWindowButtonType.zoomButton,
      offset: const Offset(60, _customButtonY),
    );
  }

  /// 为全屏模式准备标题栏
  void _prepareForFullscreen() {
    WindowManipulator.removeToolbar();
    WindowManipulator.showTitle();
    WindowManipulator.makeTitlebarOpaque();

    // 将红绿灯按钮设置为标准全屏位置 (null = 默认)
    WindowManipulator.overrideStandardWindowButtonPosition(buttonType: NSWindowButtonType.closeButton, offset: null);
    WindowManipulator.overrideStandardWindowButtonPosition(
      buttonType: NSWindowButtonType.miniaturizeButton,
      offset: null,
    );
    WindowManipulator.overrideStandardWindowButtonPosition(buttonType: NSWindowButtonType.zoomButton, offset: null);
  }
}
