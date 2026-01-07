import 'package:flutter/material.dart';
import 'package:rate_limiter/rate_limiter.dart';

import '../mpv/mpv.dart';

import '../models/plex_media_version.dart';
import '../utils/app_logger.dart';

/// 管理视频滤镜、缩放模式和字幕位置的服务。
///
/// 该服务处理：
/// - 循环切换 BoxFit 模式 (包含 → 覆盖 → 填充)
/// - 填充屏幕模式下的视频裁剪计算
/// - 根据裁剪参数调整字幕位置
/// - 调整大小时去抖动的视频滤镜更新
class VideoFilterManager {
  final Player player;
  final List<PlexMediaVersion> availableVersions;
  final int selectedMediaIndex;

  /// BoxFit 模式状态：0=包含 (信箱模式), 1=覆盖 (填充屏幕), 2=填充 (拉伸)
  int _boxFitMode = 0;

  /// 跟踪是否正在进行捏合手势 (公开用于手势跟踪)
  bool isPinching = false;

  /// 当前播放器视口大小
  Size? _playerSize;

  /// 带有领先执行的去抖动视频滤镜更新
  late final Debounce _debouncedUpdateVideoFilter;

  VideoFilterManager({required this.player, required this.availableVersions, required this.selectedMediaIndex}) {
    _debouncedUpdateVideoFilter = debounce(
      updateVideoFilter,
      const Duration(milliseconds: 50),
      leading: true,
      trailing: true,
    );
  }

  /// 当前 BoxFit 模式 (0=包含, 1=覆盖, 2=填充)
  int get boxFitMode => _boxFitMode;

  /// 当前播放器大小
  Size? get playerSize => _playerSize;

  /// 循环切换 BoxFit 模式：包含 → 覆盖 → 填充 → 包含 (用于按钮)
  void cycleBoxFitMode() {
    _boxFitMode = (_boxFitMode + 1) % 3;
    updateVideoFilter();
  }

  /// 仅在包含和覆盖模式之间切换 (用于捏合手势)
  void toggleContainCover() {
    _boxFitMode = _boxFitMode == 0 ? 1 : 0;
    updateVideoFilter();
  }

  /// 当布局更改时更新播放器大小
  void updatePlayerSize(Size size) {
    // 检查大小是否真的改变，以避免不必要的更新
    if (_playerSize == null ||
        (_playerSize!.width - size.width).abs() > 0.1 ||
        (_playerSize!.height - size.height).abs() > 0.1) {
      _playerSize = size;
      debouncedUpdateVideoFilter();
    }
  }

  /// 根据当前显示模式更新视频缩放和定位
  void updateVideoFilter() async {
    try {
      // 首先清除所有视频滤镜和手动缩放
      await player.setProperty('video-aspect-override', 'no');
      await player.setProperty('sub-ass-force-margins', 'no');
      await player.setProperty('panscan', '0');

      if (_boxFitMode == 1) {
        // 覆盖模式 - 使用 panscan 填充屏幕，同时保持纵横比
        await player.setProperty('panscan', '1.0');
        await player.setProperty('sub-ass-force-margins', 'yes');
      } else if (_boxFitMode == 2) {
        // 填充/拉伸模式 - 覆盖纵横比以匹配播放器 (拉伸视频)
        if (_playerSize != null) {
          final playerAspect = _playerSize!.width / _playerSize!.height;
          await player.setProperty('video-aspect-override', playerAspect.toString());
          appLogger.d('拉伸模式: aspect-override=$playerAspect (播放器: $_playerSize)');
        }
      }
    } catch (e) {
      appLogger.w('更新视频滤镜失败', error: e);
    }
  }

  /// 调整大小事件的 updateVideoFilter 去抖动版本。
  /// 使用领先执行去抖动：第一次调用立即执行，
  /// 50ms 内的后续调用将被去抖动。
  void debouncedUpdateVideoFilter() => _debouncedUpdateVideoFilter();

  /// 清理资源
  void dispose() {
    _debouncedUpdateVideoFilter.cancel();
  }
}
