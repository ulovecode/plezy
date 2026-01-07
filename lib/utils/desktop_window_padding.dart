import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../services/fullscreen_state_manager.dart';

/// InheritedWidget，用于指示组件树中存在侧边导航栏。
/// 当存在时，应用栏（App Bar）应跳过其左侧内边距，因为侧边导航栏
/// 已经处理了 macOS 的红绿灯（控制按钮）区域。
class SideNavigationScope extends InheritedWidget {
  const SideNavigationScope({super.key, required super.child});

  static bool isPresent(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SideNavigationScope>() != null;
  }

  @override
  bool updateShouldNotify(SideNavigationScope oldWidget) => false;
}

/// 桌面窗口控件的内边距值
class DesktopWindowPadding {
  /// macOS 红绿灯按钮的左侧内边距（普通窗口模式）
  static const double macOSLeft = 80.0;

  /// macOS 全屏模式下的左侧内边距（由于红绿灯按钮会自动隐藏，因此内边距减少）
  static const double macOSLeftFullscreen = 0.0;

  /// macOS 的右侧内边距，防止操作按钮过于靠近边缘
  static const double macOSRight = 16.0;

  /// 移动设备的右侧内边距，防止操作按钮过于靠近边缘
  static const double mobileRight = 6.0;
}

/// 辅助类，用于调整应用栏组件以适应桌面窗口控件
class DesktopAppBarHelper {
  /// 构建具有适用于 macOS 和移动设备的右侧内边距的操作按钮列表
  static List<Widget>? buildAdjustedActions(List<Widget>? actions) {
    double? rightPadding;

    if (Platform.isMacOS) {
      rightPadding = DesktopWindowPadding.macOSRight;
    } else if (Platform.isIOS || Platform.isAndroid) {
      rightPadding = DesktopWindowPadding.mobileRight;
    }

    // 如果不需要特定平台的内边距，则返回原始操作按钮列表
    if (rightPadding == null) {
      return actions;
    }

    // 添加内边距以使操作按钮远离边缘
    if (actions != null) {
      return [...actions, SizedBox(width: rightPadding)];
    } else {
      return [SizedBox(width: rightPadding)];
    }
  }

  /// 构建具有适用于 macOS 红绿灯按钮的左侧内边距的前置组件（leading widget）
  ///
  /// [includeGestureDetector] - 如果为 true，则使用 GestureDetector 包裹以防止窗口拖动
  /// [context] - 需要用来检查侧边导航栏是否可见
  static Widget? buildAdjustedLeading(Widget? leading, {bool includeGestureDetector = false, BuildContext? context}) {
    if (!Platform.isMacOS || leading == null) {
      return leading;
    }

    // 当组件树中存在侧边导航栏范围时，跳过左侧内边距
    if (context != null && SideNavigationScope.isPresent(context)) {
      if (includeGestureDetector) {
        return GestureDetector(behavior: HitTestBehavior.opaque, onPanDown: (_) {}, child: leading);
      }
      return leading;
    }

    return ListenableBuilder(
      listenable: FullscreenStateManager(),
      builder: (context, _) {
        final isFullscreen = FullscreenStateManager().isFullscreen;
        final leftPadding = isFullscreen ? DesktopWindowPadding.macOSLeftFullscreen : DesktopWindowPadding.macOSLeft;

        final paddedWidget = Padding(
          padding: EdgeInsets.only(left: leftPadding),
          child: leading,
        );

        if (includeGestureDetector) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (_) {}, // 消耗平移手势以防止窗口拖动
            child: paddedWidget,
          );
        }

        return paddedWidget;
      },
    );
  }

  /// 构建具有手势检测器的弹性空间（flexible space），在 macOS 上防止窗口拖动
  static Widget? buildAdjustedFlexibleSpace(Widget? flexibleSpace) {
    if (!Platform.isMacOS || flexibleSpace == null) {
      return flexibleSpace;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanDown: (_) {}, // 消耗平移手势以防止窗口拖动
      child: flexibleSpace,
    );
  }

  /// 计算 SliverAppBar 的前置组件宽度，以适应 macOS 红绿灯按钮
  /// [context] - 需要用来检查侧边导航栏是否可见
  static double? calculateLeadingWidth(Widget? leading, {BuildContext? context}) {
    if (!Platform.isMacOS || leading == null) {
      return null;
    }

    // 当组件树中存在侧边导航栏范围时，跳过额外宽度
    if (context != null && SideNavigationScope.isPresent(context)) {
      return null;
    }

    final isFullscreen = FullscreenStateManager().isFullscreen;
    final leftPadding = isFullscreen ? DesktopWindowPadding.macOSLeftFullscreen : DesktopWindowPadding.macOSLeft;
    return leftPadding + kToolbarHeight;
  }

  /// 在 macOS 上使用 GestureDetector 包裹组件以防止窗口拖动
  ///
  /// [opaque] - 如果为 true，则使用 HitTestBehavior.opaque 完全消耗手势。
  ///            如果为 false（默认值），则使用 HitTestBehavior.translucent。
  static Widget wrapWithGestureDetector(Widget child, {bool opaque = false}) {
    if (!Platform.isMacOS) {
      return child;
    }

    return GestureDetector(
      behavior: opaque ? HitTestBehavior.opaque : HitTestBehavior.translucent,
      onPanDown: (_) {}, // 消耗平移手势以防止窗口拖动
      child: child,
    );
  }
}

/// 一个添加内边距以适应桌面窗口控件的组件。
/// 在 macOS 上，为红绿灯按钮添加左侧内边距（全屏模式下会减少）。
/// 当侧边导航栏可见时，会跳过左侧内边距，因为侧边导航栏已经占据了红绿灯区域。
class DesktopTitleBarPadding extends StatelessWidget {
  final Widget child;
  final double? leftPadding;
  final double? rightPadding;

  const DesktopTitleBarPadding({super.key, required this.child, this.leftPadding, this.rightPadding});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return child;
    }

    // Skip left padding when side navigation scope is present in widget tree
    // (side nav already handles the traffic lights area)
    if (SideNavigationScope.isPresent(context)) {
      final right = rightPadding ?? 0.0;
      if (right == 0.0) {
        return child;
      }
      return Padding(
        padding: EdgeInsets.only(right: right),
        child: child,
      );
    }

    return ListenableBuilder(
      listenable: FullscreenStateManager(),
      builder: (context, _) {
        final isFullscreen = FullscreenStateManager().isFullscreen;
        // In fullscreen, use minimal padding since traffic lights auto-hide
        final left =
            leftPadding ?? (isFullscreen ? DesktopWindowPadding.macOSLeftFullscreen : DesktopWindowPadding.macOSLeft);
        final right = rightPadding ?? 0.0;

        if (left == 0.0 && right == 0.0) {
          return child;
        }

        return Padding(
          padding: EdgeInsets.only(left: left, right: right),
          child: child,
        );
      },
    );
  }
}
