import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/settings_service.dart' as settings;
import '../theme/mono_theme.dart';

/// 用于管理应用主题（亮色/暗色/系统）的 Provider。
class ThemeProvider extends ChangeNotifier {
  late settings.SettingsService _settingsService;
  settings.ThemeMode _themeMode = settings.ThemeMode.system;
  late Brightness _systemBrightness;

  ThemeProvider() {
    _systemBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _initializeSettings();

    // 监听系统主题变化
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged = () {
      _systemBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      if (_themeMode == settings.ThemeMode.system) {
        notifyListeners();
      }
    };
  }

  Future<void> _initializeSettings() async {
    _settingsService = await settings.SettingsService.getInstance();
    _themeMode = _settingsService.getThemeMode();
    notifyListeners();
  }

  /// 获取当前的主题模式设置
  settings.ThemeMode get themeMode => _themeMode;

  /// 获取亮色主题数据
  ThemeData get lightTheme => monoTheme(dark: false);
  
  /// 获取暗色主题数据
  ThemeData get darkTheme => monoTheme(dark: true);

  /// 将内部主题模式转换为 Flutter 的 ThemeMode
  ThemeMode get materialThemeMode {
    switch (_themeMode) {
      case settings.ThemeMode.light:
        return ThemeMode.light;
      case settings.ThemeMode.dark:
        return ThemeMode.dark;
      case settings.ThemeMode.system:
        return ThemeMode.system;
    }
  }

  /// 判断当前是否处于暗色模式（考虑系统设置）
  bool get isDarkMode {
    switch (_themeMode) {
      case settings.ThemeMode.light:
        return false;
      case settings.ThemeMode.dark:
        return true;
      case settings.ThemeMode.system:
        return _systemBrightness == Brightness.dark;
    }
  }

  /// 设置新的主题模式并持久化
  Future<void> setThemeMode(settings.ThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      await _settingsService.setThemeMode(mode);
      notifyListeners();
    }
  }

  /// 获取主题模式的本地化显示名称
  String get themeModeDisplayName {
    switch (_themeMode) {
      case settings.ThemeMode.light:
        return '浅色';
      case settings.ThemeMode.dark:
        return '深色';
      case settings.ThemeMode.system:
        return '系统';
    }
  }

  /// 获取对应主题模式的图标
  IconData get themeModeIcon {
    switch (_themeMode) {
      case settings.ThemeMode.light:
        return Symbols.light_mode_rounded;
      case settings.ThemeMode.dark:
        return Symbols.dark_mode_rounded;
      case settings.ThemeMode.system:
        return Symbols.brightness_auto_rounded;
    }
  }

  /// 在 浅色 -> 深色 -> 系统 模式之间循环切换
  void toggleTheme() {
    switch (_themeMode) {
      case settings.ThemeMode.system:
        setThemeMode(settings.ThemeMode.light);
        break;
      case settings.ThemeMode.light:
        setThemeMode(settings.ThemeMode.dark);
        break;
      case settings.ThemeMode.dark:
        setThemeMode(settings.ThemeMode.system);
        break;
    }
  }
}
