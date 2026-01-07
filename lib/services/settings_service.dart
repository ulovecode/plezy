import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:plezy/utils/app_logger.dart';
import '../i18n/strings.g.dart';
import '../models/mpv_config_models.dart';
import 'base_shared_preferences_service.dart';
import '../utils/platform_detector.dart';

enum ThemeMode { system, light, dark }

enum LibraryDensity { compact, normal, comfortable }

enum ViewMode { grid, list }

/// 设置服务，继承自 BaseSharedPreferencesService，用于管理应用的所有用户偏好设置。
class SettingsService extends BaseSharedPreferencesService {
  // 存储键名常量
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyEnableDebugLogging = 'enable_debug_logging';
  static const String _keyBufferSize = 'buffer_size';
  static const String _keyKeyboardShortcuts = 'keyboard_shortcuts';
  static const String _keyKeyboardHotkeys = 'keyboard_hotkeys';
  static const String _keyEnableHardwareDecoding = 'enable_hardware_decoding';
  static const String _keyEnableHDR = 'enable_hdr';
  static const String _keyPreferredVideoCodec = 'preferred_video_codec';
  static const String _keyPreferredAudioCodec = 'preferred_audio_codec';
  static const String _keyLibraryDensity = 'library_density';
  static const String _keyViewMode = 'view_mode';
  static const String _keyUseSeasonPoster = 'use_season_poster';
  static const String _keySeekTimeSmall = 'seek_time_small';
  static const String _keySeekTimeLarge = 'seek_time_large';
  static const String _keyMediaVersionPreferences = 'media_version_preferences';
  static const String _keyShowHeroSection = 'show_hero_section';
  static const String _keySleepTimerDuration = 'sleep_timer_duration';
  static const String _keyAudioSyncOffset = 'audio_sync_offset';
  static const String _keySubtitleSyncOffset = 'subtitle_sync_offset';
  static const String _keyVolume = 'volume';
  static const String _keyRotationLocked = 'rotation_locked';
  static const String _keySubtitleFontSize = 'subtitle_font_size';
  static const String _keySubtitleTextColor = 'subtitle_text_color';
  static const String _keySubtitleBorderSize = 'subtitle_border_size';
  static const String _keySubtitleBorderColor = 'subtitle_border_color';
  static const String _keySubtitleBackgroundColor = 'subtitle_background_color';
  static const String _keySubtitleBackgroundOpacity = 'subtitle_background_opacity';
  static const String _keyAppLocale = 'app_locale';
  static const String _keyRememberTrackSelections = 'remember_track_selections';
  static const String _keyAutoSkipIntro = 'auto_skip_intro';
  static const String _keyAutoSkipCredits = 'auto_skip_credits';
  static const String _keyAutoSkipDelay = 'auto_skip_delay';
  static const String _keyCustomDownloadPath = 'custom_download_path';
  static const String _keyCustomDownloadPathType = 'custom_download_path_type';
  static const String _keyDownloadOnWifiOnly = 'download_on_wifi_only';
  static const String _keyVideoPlayerNavigationEnabled = 'video_player_navigation_enabled';
  static const String _keyShowPerformanceOverlay = 'show_performance_overlay';
  static const String _keyMpvConfigEntries = 'mpv_config_entries';
  static const String _keyMpvConfigPresets = 'mpv_config_presets';
  static const String _keyMaxVolume = 'max_volume';
  static const String _keyEnableDiscordRPC = 'enable_discord_rpc';

  SettingsService._();

  /// 获取 SettingsService 单例
  static Future<SettingsService> getInstance() async {
    return BaseSharedPreferencesService.initializeInstance(() => SettingsService._());
  }

  /// 从偏好设置中获取枚举值的通用辅助方法
  T _getEnumValue<T extends Enum>(String key, List<T> values, T defaultValue) {
    final stored = prefs.getString(key);
    if (stored == null) return defaultValue;
    return values.firstWhere((v) => v.name == stored, orElse: () => defaultValue);
  }

  // 主题模式管理
  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    await prefs.setString(_keyThemeMode, mode.name);
  }

  /// 获取主题模式
  ThemeMode getThemeMode() {
    return _getEnumValue(_keyThemeMode, ThemeMode.values, ThemeMode.system);
  }

  // 调试日志管理
  /// 设置是否启用调试日志
  Future<void> setEnableDebugLogging(bool enabled) async {
    await prefs.setBool(_keyEnableDebugLogging, enabled);
    // 设置变更时立即更新日志级别
    setLoggerLevel(enabled);
  }

  /// 获取是否启用调试日志
  bool getEnableDebugLogging() {
    return prefs.getBool(_keyEnableDebugLogging) ?? false;
  }

  // 播放缓冲区大小（单位：MB）
  /// 设置缓冲区大小
  Future<void> setBufferSize(int sizeInMB) async {
    await prefs.setInt(_keyBufferSize, sizeInMB);
  }

  /// 获取缓冲区大小
  int getBufferSize() {
    return prefs.getInt(_keyBufferSize) ?? 128; // 默认 128MB
  }

  // 硬件解码管理
  /// 设置是否启用硬件解码
  Future<void> setEnableHardwareDecoding(bool enabled) async {
    await prefs.setBool(_keyEnableHardwareDecoding, enabled);
  }

  /// 获取是否启用硬件解码
  bool getEnableHardwareDecoding() {
    return prefs.getBool(_keyEnableHardwareDecoding) ?? true; // 默认启用
  }

  // HDR (高动态范围) 管理
  /// 设置是否启用 HDR
  Future<void> setEnableHDR(bool enabled) async {
    await prefs.setBool(_keyEnableHDR, enabled);
  }

  /// 获取是否启用 HDR
  bool getEnableHDR() {
    return prefs.getBool(_keyEnableHDR) ?? true; // 默认启用
  }

  // 首选视频解码器
  /// 设置首选视频解码器
  Future<void> setPreferredVideoCodec(String codec) async {
    await prefs.setString(_keyPreferredVideoCodec, codec);
  }

  /// 获取首选视频解码器
  String getPreferredVideoCodec() {
    return prefs.getString(_keyPreferredVideoCodec) ?? 'auto';
  }

  // 首选音频解码器
  /// 设置首选音频解码器
  Future<void> setPreferredAudioCodec(String codec) async {
    await prefs.setString(_keyPreferredAudioCodec, codec);
  }

  /// 获取首选音频解码器
  String getPreferredAudioCodec() {
    return prefs.getString(_keyPreferredAudioCodec) ?? 'auto';
  }

  // 媒体库显示密度设置
  /// 设置媒体库显示密度
  Future<void> setLibraryDensity(LibraryDensity density) async {
    await prefs.setString(_keyLibraryDensity, density.name);
  }

  /// 获取媒体库显示密度
  LibraryDensity getLibraryDensity() {
    return _getEnumValue(_keyLibraryDensity, LibraryDensity.values, LibraryDensity.normal);
  }

  // 视图模式管理 (网格/列表)
  /// 设置视图模式
  Future<void> setViewMode(ViewMode mode) async {
    await prefs.setString(_keyViewMode, mode.name);
  }

  /// 获取视图模式
  ViewMode getViewMode() {
    return _getEnumValue(_keyViewMode, ViewMode.values, ViewMode.grid);
  }

  // 季封面管理
  /// 设置是否使用季封面 (false 则使用剧集封面)
  Future<void> setUseSeasonPoster(bool enabled) async {
    await prefs.setBool(_keyUseSeasonPoster, enabled);
  }

  /// 获取是否使用季封面
  bool getUseSeasonPoster() {
    return prefs.getBool(_keyUseSeasonPoster) ?? false; // 默认 false
  }

  // 首页 Hero 区域管理
  /// 设置是否显示首页 Hero 区域
  Future<void> setShowHeroSection(bool enabled) async {
    await prefs.setBool(_keyShowHeroSection, enabled);
  }

  /// 获取是否显示首页 Hero 区域
  bool getShowHeroSection() {
    return prefs.getBool(_keyShowHeroSection) ?? true; // 默认显示
  }

  // 短距离快进/快退时间 (秒)
  /// 设置短距离快进/快退时间
  Future<void> setSeekTimeSmall(int seconds) async {
    await prefs.setInt(_keySeekTimeSmall, seconds);
  }

  /// 获取短距离快进/快退时间
  int getSeekTimeSmall() {
    return prefs.getInt(_keySeekTimeSmall) ?? 10; // 默认 10 秒
  }

  // 长距离快进/快退时间 (秒)
  /// 设置长距离快进/快退时间
  Future<void> setSeekTimeLarge(int seconds) async {
    await prefs.setInt(_keySeekTimeLarge, seconds);
  }

  /// 获取长距离快进/快退时间
  int getSeekTimeLarge() {
    return prefs.getInt(_keySeekTimeLarge) ?? 30; // 默认 30 秒
  }

  // 睡眠定时器时长 (分钟)
  /// 设置睡眠定时器时长
  Future<void> setSleepTimerDuration(int minutes) async {
    await prefs.setInt(_keySleepTimerDuration, minutes);
  }

  /// 获取睡眠定时器时长
  int getSleepTimerDuration() {
    return prefs.getInt(_keySleepTimerDuration) ?? 30; // 默认 30 分钟
  }

  // 音轨同步偏移 (毫秒)
  /// 设置音轨同步偏移
  Future<void> setAudioSyncOffset(int milliseconds) async {
    await prefs.setInt(_keyAudioSyncOffset, milliseconds);
  }

  /// 获取音轨同步偏移
  int getAudioSyncOffset() {
    return prefs.getInt(_keyAudioSyncOffset) ?? 0; // 默认 0ms
  }

  // 字幕同步偏移 (毫秒)
  /// 设置字幕同步偏移
  Future<void> setSubtitleSyncOffset(int milliseconds) async {
    await prefs.setInt(_keySubtitleSyncOffset, milliseconds);
  }

  /// 获取字幕同步偏移
  int getSubtitleSyncOffset() {
    return prefs.getInt(_keySubtitleSyncOffset) ?? 0; // 默认 0ms
  }

  // 音量管理 (0.0 到 100.0)
  /// 设置当前音量
  Future<void> setVolume(double volume) async {
    await prefs.setDouble(_keyVolume, volume);
  }

  /// 获取当前音量
  double getVolume() {
    return prefs.getDouble(_keyVolume) ?? 100.0; // 默认最大音量
  }

  // 最大音量限制 (100-300%，用于音量增益)
  /// 设置最大音量限制
  Future<void> setMaxVolume(int percent) async {
    await prefs.setInt(_keyMaxVolume, percent.clamp(100, 300));
  }

  /// 获取最大音量限制
  int getMaxVolume() {
    return prefs.getInt(_keyMaxVolume) ?? 100; // 默认 100% (不增益)
  }

  // 屏幕旋转锁定 (仅移动端)
  /// 设置是否锁定屏幕旋转
  Future<void> setRotationLocked(bool locked) async {
    await prefs.setBool(_keyRotationLocked, locked);
  }

  /// 获取是否锁定屏幕旋转
  bool getRotationLocked() {
    return prefs.getBool(_keyRotationLocked) ?? true; // 默认锁定 (仅横屏)
  }

  // 字幕样式设置

  // 字幕字体大小 (30-80)
  /// 设置字幕字体大小
  Future<void> setSubtitleFontSize(int size) async {
    await prefs.setInt(_keySubtitleFontSize, size);
  }

  /// 获取字幕字体大小
  int getSubtitleFontSize() {
    return prefs.getInt(_keySubtitleFontSize) ?? 55; // 默认 55
  }

  // 字幕文本颜色 (十六进制格式 #RRGGBB)
  /// 设置字幕文本颜色
  Future<void> setSubtitleTextColor(String color) async {
    await prefs.setString(_keySubtitleTextColor, color);
  }

  /// 获取字幕文本颜色
  String getSubtitleTextColor() {
    return prefs.getString(_keySubtitleTextColor) ?? '#FFFFFF'; // 默认白色
  }

  // 字幕边框大小 (0-5)
  /// 设置字幕边框大小
  Future<void> setSubtitleBorderSize(int size) async {
    await prefs.setInt(_keySubtitleBorderSize, size);
  }

  /// 获取字幕边框大小
  int getSubtitleBorderSize() {
    return prefs.getInt(_keySubtitleBorderSize) ?? 3; // 默认 3
  }

  // 字幕边框颜色 (十六进制格式 #RRGGBB)
  /// 设置字幕边框颜色
  Future<void> setSubtitleBorderColor(String color) async {
    await prefs.setString(_keySubtitleBorderColor, color);
  }

  /// 获取字幕边框颜色
  String getSubtitleBorderColor() {
    return prefs.getString(_keySubtitleBorderColor) ?? '#000000'; // 默认黑色
  }

  // 字幕背景颜色 (十六进制格式 #RRGGBB)
  /// 设置字幕背景颜色
  Future<void> setSubtitleBackgroundColor(String color) async {
    await prefs.setString(_keySubtitleBackgroundColor, color);
  }

  /// 获取字幕背景颜色
  String getSubtitleBackgroundColor() {
    return prefs.getString(_keySubtitleBackgroundColor) ?? '#000000'; // 默认黑色
  }

  // 字幕背景透明度 (0-100)
  /// 设置字幕背景透明度 (0 为完全透明)
  Future<void> setSubtitleBackgroundOpacity(int opacity) async {
    await prefs.setInt(_keySubtitleBackgroundOpacity, opacity);
  }

  /// 获取字幕背景透明度
  int getSubtitleBackgroundOpacity() {
    return prefs.getInt(_keySubtitleBackgroundOpacity) ?? 0;
  }

  // 键盘快捷键 (旧版字符串形式)
  /// 获取默认键盘快捷键映射
  Map<String, String> getDefaultKeyboardShortcuts() {
    return {
      'play_pause': 'Space',
      'volume_up': 'Arrow Up',
      'volume_down': 'Arrow Down',
      'seek_forward': 'Arrow Right',
      'seek_backward': 'Arrow Left',
      'seek_forward_large': 'Shift+Arrow Right',
      'seek_backward_large': 'Shift+Arrow Left',
      'fullscreen_toggle': 'F',
      'mute_toggle': 'M',
      'subtitle_toggle': 'S',
      'audio_track_next': 'A',
      'subtitle_track_next': 'Shift+S',
      'chapter_next': 'N',
      'chapter_previous': 'P',
      'speed_increase': 'Plus',
      'speed_decrease': 'Minus',
      'speed_reset': 'R',
    };
  }

  // HotKey 对象 (新版实现)
  /// 获取默认键盘热键映射 (HotKey 对象)
  Map<String, HotKey> getDefaultKeyboardHotkeys() {
    return {
      'play_pause': HotKey(key: PhysicalKeyboardKey.space),
      'volume_up': HotKey(key: PhysicalKeyboardKey.arrowUp),
      'volume_down': HotKey(key: PhysicalKeyboardKey.arrowDown),
      'seek_forward': HotKey(key: PhysicalKeyboardKey.arrowRight),
      'seek_backward': HotKey(key: PhysicalKeyboardKey.arrowLeft),
      'seek_forward_large': HotKey(key: PhysicalKeyboardKey.arrowRight, modifiers: [HotKeyModifier.shift]),
      'seek_backward_large': HotKey(key: PhysicalKeyboardKey.arrowLeft, modifiers: [HotKeyModifier.shift]),
      'fullscreen_toggle': HotKey(key: PhysicalKeyboardKey.keyF),
      'mute_toggle': HotKey(key: PhysicalKeyboardKey.keyM),
      'subtitle_toggle': HotKey(key: PhysicalKeyboardKey.keyS),
      'audio_track_next': HotKey(key: PhysicalKeyboardKey.keyA),
      'subtitle_track_next': HotKey(key: PhysicalKeyboardKey.keyS, modifiers: [HotKeyModifier.shift]),
      'chapter_next': HotKey(key: PhysicalKeyboardKey.keyN),
      'chapter_previous': HotKey(key: PhysicalKeyboardKey.keyP),
      'speed_increase': HotKey(key: PhysicalKeyboardKey.equal),
      'speed_decrease': HotKey(key: PhysicalKeyboardKey.minus),
      'speed_reset': HotKey(key: PhysicalKeyboardKey.keyR),
    };
  }

  /// 保存所有键盘快捷键 (字符串映射)
  Future<void> setKeyboardShortcuts(Map<String, String> shortcuts) async {
    final jsonString = json.encode(shortcuts);
    await prefs.setString(_keyKeyboardShortcuts, jsonString);
  }

  /// 获取所有键盘快捷键 (字符串映射)
  Map<String, String> getKeyboardShortcuts() {
    final jsonString = prefs.getString(_keyKeyboardShortcuts);
    if (jsonString == null) return getDefaultKeyboardShortcuts();

    final decoded = _decodeJsonStringToMap(jsonString);
    if (decoded.isEmpty) return getDefaultKeyboardShortcuts();

    final shortcuts = decoded.map((key, value) => MapEntry(key, value.toString()));

    // 与默认值合并以确保所有键都存在
    final defaults = getDefaultKeyboardShortcuts();
    defaults.addAll(shortcuts);
    return defaults;
  }

  /// 设置单个键盘快捷键
  Future<void> setKeyboardShortcut(String action, String key) async {
    final shortcuts = getKeyboardShortcuts();
    shortcuts[action] = key;
    await setKeyboardShortcuts(shortcuts);
  }

  /// 获取单个操作的键盘快捷键
  String getKeyboardShortcut(String action) {
    final shortcuts = getKeyboardShortcuts();
    return shortcuts[action] ?? '';
  }

  /// 重置所有键盘快捷键为默认值
  Future<void> resetKeyboardShortcuts() async {
    await setKeyboardShortcuts(getDefaultKeyboardShortcuts());
  }

  // HotKey 对象管理方法
  /// 保存所有 HotKey 映射
  Future<void> setKeyboardHotkeys(Map<String, HotKey> hotkeys) async {
    final Map<String, Map<String, dynamic>> serializedHotkeys = {};
    for (final entry in hotkeys.entries) {
      serializedHotkeys[entry.key] = _serializeHotKey(entry.value);
    }
    final jsonString = json.encode(serializedHotkeys);
    await prefs.setString(_keyKeyboardHotkeys, jsonString);
  }

  /// 获取所有 HotKey 映射
  Future<Map<String, HotKey>> getKeyboardHotkeys() async {
    final jsonString = prefs.getString(_keyKeyboardHotkeys);
    if (jsonString == null) {
      return getDefaultKeyboardHotkeys();
    }

    try {
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      final Map<String, HotKey> hotkeys = {};

      for (final entry in decoded.entries) {
        final hotKey = _deserializeHotKey(entry.value as Map<String, dynamic>);
        if (hotKey != null) {
          hotkeys[entry.key] = hotKey;
        }
      }

      // 与默认值合并以确保所有键都存在，但优先保留已保存的热键
      final defaults = getDefaultKeyboardHotkeys();
      final result = <String, HotKey>{};

      // 从默认值开始
      result.addAll(defaults);
      // 覆盖为保存的热键 (这会保留用户的自定义设置)
      result.addAll(hotkeys);

      return result;
    } catch (e) {
      return getDefaultKeyboardHotkeys();
    }
  }

  /// 设置单个 HotKey
  Future<void> setKeyboardHotkey(String action, HotKey hotKey) async {
    final hotkeys = await getKeyboardHotkeys();
    hotkeys[action] = hotKey;
    await setKeyboardHotkeys(hotkeys);
  }

  /// 获取单个操作的 HotKey
  Future<HotKey?> getKeyboardHotkey(String action) async {
    final hotkeys = await getKeyboardHotkeys();
    return hotkeys[action];
  }

  /// 重置所有 HotKey 为默认值
  Future<void> resetKeyboardHotkeys() async {
    await setKeyboardHotkeys(getDefaultKeyboardHotkeys());
  }

  // 视频播放器导航 (使用方向键导航播放器控件)
  /// 设置是否启用视频播放器导航
  Future<void> setVideoPlayerNavigationEnabled(bool enabled) async {
    await prefs.setBool(_keyVideoPlayerNavigationEnabled, enabled);
  }

  /// 获取是否启用视频播放器导航
  bool getVideoPlayerNavigationEnabled() {
    // 默认：Android TV 上启用，其他地方禁用
    return prefs.getBool(_keyVideoPlayerNavigationEnabled) ?? TvDetectionService.isTVSync();
  }

  // 性能叠加层 (在视频播放器上显示调试统计信息)
  /// 设置是否显示性能叠加层
  Future<void> setShowPerformanceOverlay(bool enabled) async {
    await prefs.setBool(_keyShowPerformanceOverlay, enabled);
  }

  /// 获取是否显示性能叠加层
  bool getShowPerformanceOverlay() {
    return prefs.getBool(_keyShowPerformanceOverlay) ?? false; // 默认禁用
  }

  // HotKey 序列化辅助方法
  static const _modifierMap = <String, HotKeyModifier>{
    'alt': HotKeyModifier.alt,
    'control': HotKeyModifier.control,
    'shift': HotKeyModifier.shift,
    'meta': HotKeyModifier.meta,
    'capsLock': HotKeyModifier.capsLock,
    'fn': HotKeyModifier.fn,
  };

  /// 将 HotKey 序列化为 Map
  Map<String, dynamic> _serializeHotKey(HotKey hotKey) {
    // 使用 USB HID 码进行可靠的序列化，支持调试/发布模式
    final physicalKey = hotKey.key as PhysicalKeyboardKey;
    final usbHidCode = physicalKey.usbHidUsage.toRadixString(16).padLeft(8, '0');
    return {'key': usbHidCode, 'modifiers': hotKey.modifiers?.map((m) => m.name).toList() ?? []};
  }

  /// 将 Map 反序列化为 HotKey
  HotKey? _deserializeHotKey(Map<String, dynamic> data) {
    try {
      final keyString = data['key'] as String;
      final modifierNames = (data['modifiers'] as List<dynamic>).cast<String>();

      final modifiers = modifierNames
          .map((name) => _modifierMap[name])
          .where((m) => m != null)
          .cast<HotKeyModifier>()
          .toList();

      // 首先尝试通过 USB HID 查找 (新格式)，失败则回退到字符串解析 (向后兼容)
      final key = _usbHidKeyMap[keyString] ?? _findKeyByString(keyString);
      if (key != null) {
        return HotKey(key: key, modifiers: modifiers.isNotEmpty ? modifiers : null);
      }
    } catch (e) {
      // 忽略反序列化错误
    }
    return null;
  }

  // 用于 USB HID 码与 PhysicalKeyboardKey 的统一映射表
  static const _usbHidKeyMap = <String, PhysicalKeyboardKey>{
    // 特殊键
    '0007002c': PhysicalKeyboardKey.space,
    '0007002a': PhysicalKeyboardKey.backspace,
    '0007004c': PhysicalKeyboardKey.delete,
    '00070028': PhysicalKeyboardKey.enter,
    '00070029': PhysicalKeyboardKey.escape,
    '0007002b': PhysicalKeyboardKey.tab,
    '00070039': PhysicalKeyboardKey.capsLock,
    // 方向键
    '00070050': PhysicalKeyboardKey.arrowLeft,
    '00070052': PhysicalKeyboardKey.arrowUp,
    '0007004f': PhysicalKeyboardKey.arrowRight,
    '00070051': PhysicalKeyboardKey.arrowDown,
    // 导航键
    '0007004a': PhysicalKeyboardKey.home,
    '0007004d': PhysicalKeyboardKey.end,
    '0007004b': PhysicalKeyboardKey.pageUp,
    '0007004e': PhysicalKeyboardKey.pageDown,
    // 符号键
    '0007002d': PhysicalKeyboardKey.equal,
    '0007002e': PhysicalKeyboardKey.minus,
    // 功能键
    '0007003a': PhysicalKeyboardKey.f1,
    '0007003b': PhysicalKeyboardKey.f2,
    '0007003c': PhysicalKeyboardKey.f3,
    '0007003d': PhysicalKeyboardKey.f4,
    '0007003e': PhysicalKeyboardKey.f5,
    '0007003f': PhysicalKeyboardKey.f6,
    '00070040': PhysicalKeyboardKey.f7,
    '00070041': PhysicalKeyboardKey.f8,
    '00070042': PhysicalKeyboardKey.f9,
    '00070043': PhysicalKeyboardKey.f10,
    '00070044': PhysicalKeyboardKey.f11,
    '00070045': PhysicalKeyboardKey.f12,
    // 数字键
    '00070027': PhysicalKeyboardKey.digit0,
    '0007001e': PhysicalKeyboardKey.digit1,
    '0007001f': PhysicalKeyboardKey.digit2,
    '00070020': PhysicalKeyboardKey.digit3,
    '00070021': PhysicalKeyboardKey.digit4,
    '00070022': PhysicalKeyboardKey.digit5,
    '00070023': PhysicalKeyboardKey.digit6,
    '00070024': PhysicalKeyboardKey.digit7,
    '00070025': PhysicalKeyboardKey.digit8,
    '00070026': PhysicalKeyboardKey.digit9,
    // 字母键
    '00070004': PhysicalKeyboardKey.keyA,
    '00070005': PhysicalKeyboardKey.keyB,
    '00070006': PhysicalKeyboardKey.keyC,
    '00070007': PhysicalKeyboardKey.keyD,
    '00070008': PhysicalKeyboardKey.keyE,
    '00070009': PhysicalKeyboardKey.keyF,
    '0007000a': PhysicalKeyboardKey.keyG,
    '0007000b': PhysicalKeyboardKey.keyH,
    '0007000c': PhysicalKeyboardKey.keyI,
    '0007000d': PhysicalKeyboardKey.keyJ,
    '0007000e': PhysicalKeyboardKey.keyK,
    '0007000f': PhysicalKeyboardKey.keyL,
    '00070010': PhysicalKeyboardKey.keyM,
    '00070011': PhysicalKeyboardKey.keyN,
    '00070012': PhysicalKeyboardKey.keyO,
    '00070013': PhysicalKeyboardKey.keyP,
    '00070014': PhysicalKeyboardKey.keyQ,
    '00070015': PhysicalKeyboardKey.keyR,
    '00070016': PhysicalKeyboardKey.keyS,
    '00070017': PhysicalKeyboardKey.keyT,
    '00070018': PhysicalKeyboardKey.keyU,
    '00070019': PhysicalKeyboardKey.keyV,
    '0007001a': PhysicalKeyboardKey.keyW,
    '0007001b': PhysicalKeyboardKey.keyX,
    '0007001c': PhysicalKeyboardKey.keyY,
    '0007001d': PhysicalKeyboardKey.keyZ,
  };

  // 用于模式匹配的按键名称映射 (小写以支持不区分大小写匹配)
  static const _keyNameMap = <String, PhysicalKeyboardKey>{
    'space': PhysicalKeyboardKey.space,
    'backspace': PhysicalKeyboardKey.backspace,
    'delete': PhysicalKeyboardKey.delete,
    'enter': PhysicalKeyboardKey.enter,
    'escape': PhysicalKeyboardKey.escape,
    'tab': PhysicalKeyboardKey.tab,
    'capslock': PhysicalKeyboardKey.capsLock,
    'arrowleft': PhysicalKeyboardKey.arrowLeft,
    'arrowup': PhysicalKeyboardKey.arrowUp,
    'arrowright': PhysicalKeyboardKey.arrowRight,
    'arrowdown': PhysicalKeyboardKey.arrowDown,
    'home': PhysicalKeyboardKey.home,
    'end': PhysicalKeyboardKey.end,
    'pageup': PhysicalKeyboardKey.pageUp,
    'pagedown': PhysicalKeyboardKey.pageDown,
    'equal': PhysicalKeyboardKey.equal,
    'minus': PhysicalKeyboardKey.minus,
  };

  // 功能键映射
  static const _functionKeyMap = <String, PhysicalKeyboardKey>{
    'f1': PhysicalKeyboardKey.f1,
    'f2': PhysicalKeyboardKey.f2,
    'f3': PhysicalKeyboardKey.f3,
    'f4': PhysicalKeyboardKey.f4,
    'f5': PhysicalKeyboardKey.f5,
    'f6': PhysicalKeyboardKey.f6,
    'f7': PhysicalKeyboardKey.f7,
    'f8': PhysicalKeyboardKey.f8,
    'f9': PhysicalKeyboardKey.f9,
    'f10': PhysicalKeyboardKey.f10,
    'f11': PhysicalKeyboardKey.f11,
    'f12': PhysicalKeyboardKey.f12,
  };

  // 数字键映射
  static const _digitKeyMap = <String, PhysicalKeyboardKey>{
    'digit0': PhysicalKeyboardKey.digit0,
    'digit1': PhysicalKeyboardKey.digit1,
    'digit2': PhysicalKeyboardKey.digit2,
    'digit3': PhysicalKeyboardKey.digit3,
    'digit4': PhysicalKeyboardKey.digit4,
    'digit5': PhysicalKeyboardKey.digit5,
    'digit6': PhysicalKeyboardKey.digit6,
    'digit7': PhysicalKeyboardKey.digit7,
    'digit8': PhysicalKeyboardKey.digit8,
    'digit9': PhysicalKeyboardKey.digit9,
  };

  // 字母键映射
  static const _letterKeyMap = <String, PhysicalKeyboardKey>{
    'keya': PhysicalKeyboardKey.keyA,
    'keyb': PhysicalKeyboardKey.keyB,
    'keyc': PhysicalKeyboardKey.keyC,
    'keyd': PhysicalKeyboardKey.keyD,
    'keye': PhysicalKeyboardKey.keyE,
    'keyf': PhysicalKeyboardKey.keyF,
    'keyg': PhysicalKeyboardKey.keyG,
    'keyh': PhysicalKeyboardKey.keyH,
    'keyi': PhysicalKeyboardKey.keyI,
    'keyj': PhysicalKeyboardKey.keyJ,
    'keyk': PhysicalKeyboardKey.keyK,
    'keyl': PhysicalKeyboardKey.keyL,
    'keym': PhysicalKeyboardKey.keyM,
    'keyn': PhysicalKeyboardKey.keyN,
    'keyo': PhysicalKeyboardKey.keyO,
    'keyp': PhysicalKeyboardKey.keyP,
    'keyq': PhysicalKeyboardKey.keyQ,
    'keyr': PhysicalKeyboardKey.keyR,
    'keys': PhysicalKeyboardKey.keyS,
    'keyt': PhysicalKeyboardKey.keyT,
    'keyu': PhysicalKeyboardKey.keyU,
    'keyv': PhysicalKeyboardKey.keyV,
    'keyw': PhysicalKeyboardKey.keyW,
    'keyx': PhysicalKeyboardKey.keyX,
    'keyy': PhysicalKeyboardKey.keyY,
    'keyz': PhysicalKeyboardKey.keyZ,
  };

  /// 通过字符串表示查找 PhysicalKeyboardKey 的辅助方法
  PhysicalKeyboardKey? _findKeyByString(String keyString) {
    final normalized = keyString.toLowerCase();

    // 尝试从 toString() 输出中提取 USB HID 码
    // 格式: PhysicalKeyboardKey#ec9ed(usbHidUsage: "0x0007002c", debugName: "Space")
    final usbHidMatch = RegExp(r'usbhidusage: "0x([0-9a-f]+)"').firstMatch(normalized);
    if (usbHidMatch != null) {
      final usbHidCode = usbHidMatch.group(1)!;
      final key = _usbHidKeyMap[usbHidCode];
      if (key != null) return key;
    }

    // 尝试直接名称匹配
    for (final entry in _keyNameMap.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    // 尝试功能键 (首先检查较长的模式以避免 f1 匹配 f10)
    for (final entry in _functionKeyMap.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    // 尝试数字键
    for (final entry in _digitKeyMap.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    // 尝试字母键
    for (final entry in _letterKeyMap.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }

  // 媒体版本偏好设置
  /// 保存剧集/电影的媒体版本选择偏好
  /// [seriesRatingKey] 对于电视剧是 grandparentRatingKey，对于电影是 ratingKey
  /// [mediaIndex] 所选媒体版本的索引
  Future<void> setMediaVersionPreference(String seriesRatingKey, int mediaIndex) async {
    final preferences = _getMediaVersionPreferences();
    preferences[seriesRatingKey] = mediaIndex;

    final jsonString = json.encode(preferences);
    await prefs.setString(_keyMediaVersionPreferences, jsonString);
  }

  /// 获取保存的剧集/电影媒体版本偏好
  /// 如果未保存则返回 null
  int? getMediaVersionPreference(String seriesRatingKey) {
    final preferences = _getMediaVersionPreferences();
    return preferences[seriesRatingKey];
  }

  /// 清除特定剧集/电影的媒体版本偏好
  Future<void> clearMediaVersionPreference(String seriesRatingKey) async {
    final preferences = _getMediaVersionPreferences();
    preferences.remove(seriesRatingKey);

    final jsonString = json.encode(preferences);
    await prefs.setString(_keyMediaVersionPreferences, jsonString);
  }

  /// 获取所有媒体版本偏好设置
  Map<String, int> _getMediaVersionPreferences() {
    final jsonString = prefs.getString(_keyMediaVersionPreferences);
    if (jsonString == null) return {};

    final decoded = _decodeJsonStringToMap(jsonString);
    return decoded.map((key, value) => MapEntry(key, value as int));
  }

  /// 带有错误处理的 JSON 字符串解码辅助方法
  Map<String, dynamic> _decodeJsonStringToMap(String jsonString) {
    try {
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  // 应用语言设置
  /// 设置应用语言
  Future<void> setAppLocale(AppLocale locale) async {
    await prefs.setString(_keyAppLocale, locale.languageCode);
  }

  /// 获取应用语言
  AppLocale getAppLocale() {
    final localeString = prefs.getString(_keyAppLocale);
    if (localeString == null) return AppLocale.en; // 默认英语

    return AppLocale.values.firstWhere((locale) => locale.languageCode == localeString, orElse: () => AppLocale.en);
  }

  // 轨道选择设置

  /// 记住轨道选择 - 是否保存每个媒体的音频/字幕语言偏好
  Future<void> setRememberTrackSelections(bool value) async {
    await prefs.setBool(_keyRememberTrackSelections, value);
  }

  /// 获取是否记住轨道选择
  bool getRememberTrackSelections() {
    return prefs.getBool(_keyRememberTrackSelections) ?? true;
  }

  // 自动跳过片头 (Intro)
  /// 设置是否自动跳过片头
  Future<void> setAutoSkipIntro(bool value) async {
    await prefs.setBool(_keyAutoSkipIntro, value);
  }

  /// 获取是否自动跳过片头
  bool getAutoSkipIntro() {
    return prefs.getBool(_keyAutoSkipIntro) ?? true; // 默认启用
  }

  // 自动跳过片尾 (Credits)
  /// 设置是否自动跳过片尾
  Future<void> setAutoSkipCredits(bool value) async {
    await prefs.setBool(_keyAutoSkipCredits, value);
  }

  /// 获取是否自动跳过片尾
  bool getAutoSkipCredits() {
    return prefs.getBool(_keyAutoSkipCredits) ?? true; // 默认启用
  }

  // 自动跳过延迟时间 (秒)
  /// 设置自动跳过前的延迟时间
  Future<void> setAutoSkipDelay(int seconds) async {
    await prefs.setInt(_keyAutoSkipDelay, seconds);
  }

  /// 获取自动跳过前的延迟时间
  int getAutoSkipDelay() {
    return prefs.getInt(_keyAutoSkipDelay) ?? 5; // 默认 5 秒
  }

  // 自定义下载路径管理
  /// 设置自定义下载路径
  Future<void> setCustomDownloadPath(String? path, {String type = 'file'}) async {
    if (path == null) {
      await prefs.remove(_keyCustomDownloadPath);
      await prefs.remove(_keyCustomDownloadPathType);
    } else {
      await prefs.setString(_keyCustomDownloadPath, path);
      await prefs.setString(_keyCustomDownloadPathType, type);
    }
  }

  /// 获取自定义下载路径
  String? getCustomDownloadPath() {
    return prefs.getString(_keyCustomDownloadPath);
  }

  /// 获取下载路径类型
  String getCustomDownloadPathType() {
    return prefs.getString(_keyCustomDownloadPathType) ?? 'file';
  }

  /// 是否已设置自定义下载路径
  bool hasCustomDownloadPath() {
    return prefs.containsKey(_keyCustomDownloadPath);
  }

  // 仅在 WiFi 下下载设置
  /// 设置是否仅在 WiFi 环境下下载
  Future<void> setDownloadOnWifiOnly(bool value) async {
    await prefs.setBool(_keyDownloadOnWifiOnly, value);
  }

  /// 获取是否仅在 WiFi 环境下下载
  bool getDownloadOnWifiOnly() {
    return prefs.getBool(_keyDownloadOnWifiOnly) ?? false;
  }

  // MPV 配置项管理

  /// 获取所有 MPV 配置项
  List<MpvConfigEntry> getMpvConfigEntries() {
    final jsonString = prefs.getString(_keyMpvConfigEntries);
    if (jsonString == null) return [];

    try {
      final List<dynamic> decoded = json.decode(jsonString);
      return decoded.map((e) => MpvConfigEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 保存所有 MPV 配置项
  Future<void> setMpvConfigEntries(List<MpvConfigEntry> entries) async {
    final jsonString = json.encode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_keyMpvConfigEntries, jsonString);
  }

  /// 获取已启用的 MPV 配置项 (用于播放器初始化)
  Map<String, String> getEnabledMpvConfigEntries() {
    final entries = getMpvConfigEntries();
    return Map.fromEntries(entries.where((e) => e.isEnabled).map((e) => MapEntry(e.key, e.value)));
  }

  // MPV 预设管理

  /// 获取所有已保存的 MPV 预设
  List<MpvPreset> getMpvPresets() {
    final jsonString = prefs.getString(_keyMpvConfigPresets);
    if (jsonString == null) return [];

    try {
      final List<dynamic> decoded = json.decode(jsonString);
      return decoded.map((e) => MpvPreset.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 保存新预设 (覆盖同名预设)
  Future<void> saveMpvPreset(String name, List<MpvConfigEntry> entries) async {
    final presets = getMpvPresets();

    // 移除同名预设
    presets.removeWhere((p) => p.name == name);

    presets.add(MpvPreset(name: name, entries: entries, createdAt: DateTime.now()));

    final jsonString = json.encode(presets.map((p) => p.toJson()).toList());
    await prefs.setString(_keyMpvConfigPresets, jsonString);
  }

  /// 按名称删除预设
  Future<void> deleteMpvPreset(String name) async {
    final presets = getMpvPresets();
    presets.removeWhere((p) => p.name == name);

    final jsonString = json.encode(presets.map((p) => p.toJson()).toList());
    await prefs.setString(_keyMpvConfigPresets, jsonString);
  }

  /// 加载预设 (替换当前配置项)
  Future<void> loadMpvPreset(String name) async {
    final presets = getMpvPresets();
    final preset = presets.firstWhere((p) => p.name == name, orElse: () => throw Exception('预设未找到: $name'));

    await setMpvConfigEntries(preset.entries);
  }

  // Discord Rich Presence (Discord 状态显示)
  /// 设置是否启用 Discord RPC
  Future<void> setEnableDiscordRPC(bool enabled) async {
    await prefs.setBool(_keyEnableDiscordRPC, enabled);
  }

  /// 获取是否启用 Discord RPC
  bool getEnableDiscordRPC() {
    return prefs.getBool(_keyEnableDiscordRPC) ?? false; // 默认禁用
  }

  // 重置所有设置为默认值
  /// 将应用所有设置恢复为默认状态
  Future<void> resetAllSettings() async {
    await Future.wait([
      prefs.remove(_keyThemeMode),
      prefs.remove(_keyEnableDebugLogging),
      prefs.remove(_keyBufferSize),
      prefs.remove(_keyKeyboardShortcuts),
      prefs.remove(_keyKeyboardHotkeys),
      prefs.remove(_keyEnableHardwareDecoding),
      prefs.remove(_keyEnableHDR),
      prefs.remove(_keyPreferredVideoCodec),
      prefs.remove(_keyPreferredAudioCodec),
      prefs.remove(_keyLibraryDensity),
      prefs.remove(_keyViewMode),
      prefs.remove(_keyUseSeasonPoster),
      prefs.remove(_keyShowHeroSection),
      prefs.remove(_keySeekTimeSmall),
      prefs.remove(_keySeekTimeLarge),
      prefs.remove(_keyMediaVersionPreferences),
      prefs.remove(_keySleepTimerDuration),
      prefs.remove(_keyAudioSyncOffset),
      prefs.remove(_keySubtitleSyncOffset),
      prefs.remove(_keyVolume),
      prefs.remove(_keyMaxVolume),
      prefs.remove(_keySubtitleFontSize),
      prefs.remove(_keySubtitleTextColor),
      prefs.remove(_keySubtitleBorderSize),
      prefs.remove(_keySubtitleBorderColor),
      prefs.remove(_keySubtitleBackgroundColor),
      prefs.remove(_keySubtitleBackgroundOpacity),
      prefs.remove(_keyAppLocale),
      prefs.remove(_keyRememberTrackSelections),
      prefs.remove(_keyCustomDownloadPath),
      prefs.remove(_keyCustomDownloadPathType),
      prefs.remove(_keyDownloadOnWifiOnly),
      prefs.remove(_keyVideoPlayerNavigationEnabled),
      prefs.remove(_keyShowPerformanceOverlay),
      prefs.remove(_keyMpvConfigEntries),
      prefs.remove(_keyMpvConfigPresets),
      prefs.remove(_keyEnableDiscordRPC),
    ]);
  }

  // 清除缓存 (用于存储清理)
  /// 清除缓存数据
  Future<void> clearCache() async {
    // 这里将来会扩展为清理各种缓存目录
    // 目前仅清除任何与缓存相关的偏好设置
    await Future.wait([
      // 在此处添加缓存清理逻辑
    ]);
  }

  // 获取所有设置为 Map 格式 (用于调试或导出)
  /// 获取应用当前所有设置的快照
  Future<Map<String, dynamic>> getAllSettings() async {
    final hotkeys = await getKeyboardHotkeys();
    return {
      'themeMode': getThemeMode().name,
      'enableDebugLogging': getEnableDebugLogging(),
      'bufferSize': getBufferSize(),
      'enableHardwareDecoding': getEnableHardwareDecoding(),
      'preferredVideoCodec': getPreferredVideoCodec(),
      'preferredAudioCodec': getPreferredAudioCodec(),
      'libraryDensity': getLibraryDensity().name,
      'viewMode': getViewMode().name,
      'useSeasonPoster': getUseSeasonPoster(),
      'seekTimeSmall': getSeekTimeSmall(),
      'seekTimeLarge': getSeekTimeLarge(),
      'keyboardShortcuts': getKeyboardShortcuts(),
      'keyboardHotkeys': hotkeys.map((key, value) => MapEntry(key, _serializeHotKey(value))),
      'rememberTrackSelections': getRememberTrackSelections(),
      'autoSkipIntro': getAutoSkipIntro(),
      'autoSkipCredits': getAutoSkipCredits(),
      'autoSkipDelay': getAutoSkipDelay(),
    };
  }
}
