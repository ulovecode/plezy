import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../mpv/mpv.dart';
import 'settings_service.dart';
import '../utils/player_utils.dart';

/// 键盘快捷键服务类，管理播放器的快捷键映射和处理。
class KeyboardShortcutsService {
  static KeyboardShortcutsService? _instance;
  late SettingsService _settingsService;
  Map<String, String> _shortcuts = {}; // 用于向后兼容的旧版字符串快捷键
  Map<String, HotKey> _hotkeys = {}; // 新版 HotKey 对象
  int _seekTimeSmall = 10; // 默认值，从设置中加载
  int _seekTimeLarge = 30; // 默认值，从设置中加载
  int _maxVolume = 100; // 默认值，从设置中加载 (100-300%)

  KeyboardShortcutsService._();

  static Future<KeyboardShortcutsService> getInstance() async {
    if (_instance == null) {
      _instance = KeyboardShortcutsService._();
      await _instance!._init();
    }
    return _instance!;
  }

  /// 仅桌面端平台支持键盘快捷键自定义。
  static bool isPlatformSupported() {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  Future<void> _init() async {
    _settingsService = await SettingsService.getInstance();
    // 确保在加载数据前，设置服务已完全初始化
    await Future.delayed(Duration.zero); // 允许事件循环完成
    _shortcuts = _settingsService.getKeyboardShortcuts(); // 保留用于旧版兼容性
    _hotkeys = await _settingsService.getKeyboardHotkeys(); // 主要方法
    _seekTimeSmall = _settingsService.getSeekTimeSmall();
    _seekTimeLarge = _settingsService.getSeekTimeLarge();
    _maxVolume = _settingsService.getMaxVolume();
  }

  Map<String, String> get shortcuts => Map.from(_shortcuts);
  Map<String, HotKey> get hotkeys => Map.from(_hotkeys);

  String getShortcut(String action) {
    return _shortcuts[action] ?? '';
  }

  HotKey? getHotkey(String action) {
    return _hotkeys[action];
  }

  Future<void> setShortcut(String action, String key) async {
    _shortcuts[action] = key;
    await _settingsService.setKeyboardShortcuts(_shortcuts);
  }

  Future<void> setHotkey(String action, HotKey hotkey) async {
    // 首先更新本地缓存
    _hotkeys[action] = hotkey;

    // 保存到持久化存储
    await _settingsService.setKeyboardHotkey(action, hotkey);

    // 验证本地缓存是否仍然正确
    if (_hotkeys[action] != hotkey) {
      _hotkeys[action] = hotkey; // 恢复正确的值
    }
  }

  Future<void> refreshFromStorage() async {
    _hotkeys = await _settingsService.getKeyboardHotkeys();
    _seekTimeSmall = _settingsService.getSeekTimeSmall();
    _seekTimeLarge = _settingsService.getSeekTimeLarge();
  }

  Future<void> resetToDefaults() async {
    _shortcuts = _settingsService.getDefaultKeyboardShortcuts();
    _hotkeys = _settingsService.getDefaultKeyboardHotkeys();
    await _settingsService.setKeyboardShortcuts(_shortcuts);
    await _settingsService.setKeyboardHotkeys(_hotkeys);
    // 刷新缓存以确保一致性
    await refreshFromStorage();
  }

  // 格式化 HotKey 用于显示
  String formatHotkey(HotKey? hotKey) {
    if (hotKey == null) return '未设置快捷键';

    final modifiers = <String>[];
    for (final modifier in hotKey.modifiers ?? []) {
      switch (modifier) {
        case HotKeyModifier.alt:
          modifiers.add('Alt');
          break;
        case HotKeyModifier.control:
          modifiers.add('Ctrl');
          break;
        case HotKeyModifier.shift:
          modifiers.add('Shift');
          break;
        case HotKeyModifier.meta:
          modifiers.add('Meta');
          break;
        case HotKeyModifier.capsLock:
          modifiers.add('CapsLock');
          break;
        case HotKeyModifier.fn:
          modifiers.add('Fn');
          break;
      }
    }

    // 格式化按键名称
    String keyName = hotKey.key.keyLabel;
    if (keyName.startsWith('PhysicalKeyboardKey#')) {
      keyName = keyName.substring(20, keyName.length - 1);
    }
    if (keyName.startsWith('key')) {
      keyName = keyName.substring(3).toUpperCase();
    }

    // 常见按键的特殊处理
    switch (keyName.toLowerCase()) {
      case 'space':
        keyName = '空格';
        break;
      case 'arrowup':
        keyName = '上方向键';
        break;
      case 'arrowdown':
        keyName = '下方向键';
        break;
      case 'arrowleft':
        keyName = '左方向键';
        break;
      case 'arrowright':
        keyName = '右方向键';
        break;
      case 'equal':
        keyName = '加号';
        break;
      case 'minus':
        keyName = '减号';
        break;
    }

    return modifiers.isEmpty ? keyName : '${modifiers.join(' + ')} + $keyName';
  }

  // 处理视频播放器的键盘输入
  KeyEventResult handleVideoPlayerKeyEvent(
    KeyEvent event,
    Player player,
    VoidCallback? onToggleFullscreen,
    VoidCallback? onToggleSubtitles,
    VoidCallback? onNextAudioTrack,
    VoidCallback? onNextSubtitleTrack,
    VoidCallback? onNextChapter,
    VoidCallback? onPreviousChapter, {
    VoidCallback? onBack,
  }) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // 处理返回导航键 (Escape)
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      onBack?.call();
      return KeyEventResult.handled;
    }

    final physicalKey = event.physicalKey;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;

    // 检查每一个热键
    for (final entry in _hotkeys.entries) {
      final action = entry.key;
      final hotkey = entry.value;

      // 检查物理按键是否匹配
      if (physicalKey != hotkey.key) continue;

      // 检查修饰键是否匹配
      final requiredModifiers = hotkey.modifiers ?? [];
      bool modifiersMatch = true;

      // 检查每一个必需的修饰键
      for (final modifier in requiredModifiers) {
        switch (modifier) {
          case HotKeyModifier.shift:
            if (!isShiftPressed) modifiersMatch = false;
            break;
          case HotKeyModifier.control:
            if (!isControlPressed) modifiersMatch = false;
            break;
          case HotKeyModifier.alt:
            if (!isAltPressed) modifiersMatch = false;
            break;
          case HotKeyModifier.meta:
            if (!isMetaPressed) modifiersMatch = false;
            break;
          case HotKeyModifier.capsLock:
            // CapsLock 通常不用于快捷键，暂时忽略
            break;
          case HotKeyModifier.fn:
            // Fn 键通常不用于快捷键，暂时忽略
            break;
        }
        if (!modifiersMatch) break;
      }

      // 检查没有按下额外的修饰键
      if (modifiersMatch) {
        final hasShift = requiredModifiers.contains(HotKeyModifier.shift);
        final hasControl = requiredModifiers.contains(HotKeyModifier.control);
        final hasAlt = requiredModifiers.contains(HotKeyModifier.alt);
        final hasMeta = requiredModifiers.contains(HotKeyModifier.meta);

        if (isShiftPressed != hasShift ||
            isControlPressed != hasControl ||
            isAltPressed != hasAlt ||
            isMetaPressed != hasMeta) {
          continue;
        }

        _executeAction(
          action,
          player,
          onToggleFullscreen,
          onToggleSubtitles,
          onNextAudioTrack,
          onNextSubtitleTrack,
          onNextChapter,
          onPreviousChapter,
        );
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _executeAction(
    String action,
    Player player,
    VoidCallback? onToggleFullscreen,
    VoidCallback? onToggleSubtitles,
    VoidCallback? onNextAudioTrack,
    VoidCallback? onNextSubtitleTrack,
    VoidCallback? onNextChapter,
    VoidCallback? onPreviousChapter,
  ) {
    switch (action) {
      case 'play_pause':
        player.playOrPause();
        break;
      case 'volume_up':
        final newVolume = (player.state.volume + 10).clamp(0.0, _maxVolume.toDouble());
        player.setVolume(newVolume);
        _settingsService.setVolume(newVolume);
        break;
      case 'volume_down':
        final newVolume = (player.state.volume - 10).clamp(0.0, _maxVolume.toDouble());
        player.setVolume(newVolume);
        _settingsService.setVolume(newVolume);
        break;
      case 'seek_forward':
        seekWithClamping(player, Duration(seconds: _seekTimeSmall));
        break;
      case 'seek_backward':
        seekWithClamping(player, Duration(seconds: -_seekTimeSmall));
        break;
      case 'seek_forward_large':
        seekWithClamping(player, Duration(seconds: _seekTimeLarge));
        break;
      case 'seek_backward_large':
        seekWithClamping(player, Duration(seconds: -_seekTimeLarge));
        break;
      case 'fullscreen_toggle':
        onToggleFullscreen?.call();
        break;
      case 'mute_toggle':
        final newVolume = player.state.volume > 0 ? 0.0 : 100.0;
        player.setVolume(newVolume);
        _settingsService.setVolume(newVolume);
        break;
      case 'subtitle_toggle':
        onToggleSubtitles?.call();
        break;
      case 'audio_track_next':
        onNextAudioTrack?.call();
        break;
      case 'subtitle_track_next':
        onNextSubtitleTrack?.call();
        break;
      case 'chapter_next':
        onNextChapter?.call();
        break;
      case 'chapter_previous':
        onPreviousChapter?.call();
        break;
      case 'speed_increase':
        final newRate = (player.state.rate + 0.1).clamp(0.1, 3.0);
        player.setRate(newRate);
        break;
      case 'speed_decrease':
        final newRate = (player.state.rate - 0.1).clamp(0.1, 3.0);
        player.setRate(newRate);
        break;
      case 'speed_reset':
        player.setRate(1.0);
        break;
    }
  }

  // 获取人类可读的操作名称
  String getActionDisplayName(String action) {
    switch (action) {
      case 'play_pause':
        return '播放/暂停';
      case 'volume_up':
        return '音量调大';
      case 'volume_down':
        return '音量调小';
      case 'seek_forward':
        return '前进 (${_seekTimeSmall}秒)';
      case 'seek_backward':
        return '后退 (${_seekTimeSmall}秒)';
      case 'seek_forward_large':
        return '大幅前进 (${_seekTimeLarge}秒)';
      case 'seek_backward_large':
        return '大幅后退 (${_seekTimeLarge}秒)';
      case 'fullscreen_toggle':
        return '切换全屏';
      case 'mute_toggle':
        return '切换静音';
      case 'subtitle_toggle':
        return '切换字幕';
      case 'audio_track_next':
        return '下一个音轨';
      case 'subtitle_track_next':
        return '下一个字幕轨';
      case 'chapter_next':
        return '下一章节';
      case 'chapter_previous':
        return '前一章节';
      case 'speed_increase':
        return '提高倍速';
      case 'speed_decrease':
        return '降低倍速';
      case 'speed_reset':
        return '重置倍速';
      default:
        return action;
    }
  }

  // 验证按键组合是否有效（用于向后兼容的旧方法）
  bool isValidKeyShortcut(String keyString) {
    // 为了向后兼容，假设所有非空字符串都是有效的
    // 新系统将使用 HotKey 对象进行验证
    return keyString.isNotEmpty;
  }

  // 检查快捷键是否已分配给另一个操作
  String? getActionForShortcut(String keyString) {
    for (final entry in _shortcuts.entries) {
      if (entry.value == keyString) {
        return entry.key;
      }
    }
    return null;
  }

  // 检查热键是否已分配给另一个操作
  String? getActionForHotkey(HotKey hotkey) {
    for (final entry in _hotkeys.entries) {
      if (_hotkeyEquals(entry.value, hotkey)) {
        return entry.key;
      }
    }
    return null;
  }

  // 用于比较两个 HotKey 对象的助手方法
  bool _hotkeyEquals(HotKey a, HotKey b) {
    if (a.key != b.key) return false;

    final aModifiers = Set.from(a.modifiers ?? []);
    final bModifiers = Set.from(b.modifiers ?? []);

    return aModifiers.length == bModifiers.length && aModifiers.every((modifier) => bModifiers.contains(modifier));
  }
}
