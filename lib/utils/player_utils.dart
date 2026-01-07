import '../mpv/mpv.dart';

/// 根据给定的偏移量（可以是正数或负数）进行跳转，
/// 同时将结果限制在 0 到视频总时长之间。
/// 返回跳转后的限制位置。
Duration seekWithClamping(Player player, Duration offset) {
  final currentPosition = player.state.position;
  final duration = player.state.duration;
  final newPosition = currentPosition + offset;

  // 限制在 0 和视频时长之间
  final clampedPosition = newPosition.isNegative ? Duration.zero : (newPosition > duration ? duration : newPosition);

  player.seek(clampedPosition);
  return clampedPosition;
}
