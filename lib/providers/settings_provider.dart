import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// 用于管理和持久化用户设置的 Provider。
class SettingsProvider extends ChangeNotifier {
  SettingsService? _settingsService;
  LibraryDensity _libraryDensity = LibraryDensity.normal;
  ViewMode _viewMode = ViewMode.grid;
  bool _useSeasonPoster = false;
  bool _showHeroSection = true;
  bool _isInitialized = false;
  Future<void>? _initFuture;

  SettingsProvider() {
    // 尽早开始初始化以减少竞态条件
    _initFuture = _initializeSettings();
  }

  /// 确保 Provider 已初始化。在需要访问实际持久化值的上下文中访问设置之前调用此方法。
  Future<void> ensureInitialized() => _initFuture ?? _initializeSettings();

  Future<void> _initializeSettings() async {
    if (_isInitialized) return;

    _settingsService = await SettingsService.getInstance();
    _libraryDensity = _settingsService!.getLibraryDensity();
    _viewMode = _settingsService!.getViewMode();
    _useSeasonPoster = _settingsService!.getUseSeasonPoster();
    _showHeroSection = _settingsService!.getShowHeroSection();
    _isInitialized = true;
    notifyListeners();
  }

  /// Provider 是否已完成初始化
  bool get isInitialized => _isInitialized;

  /// 获取库的显示密度
  LibraryDensity get libraryDensity => _libraryDensity;

  /// 获取库的视图模式（网格或列表）
  ViewMode get viewMode => _viewMode;

  /// 是否在季级视图中使用季级海报
  bool get useSeasonPoster => _useSeasonPoster;

  /// 是否显示主页面的英雄展示区
  bool get showHeroSection => _showHeroSection;

  /// 设置库的显示密度并持久化
  Future<void> setLibraryDensity(LibraryDensity density) async {
    if (!_isInitialized) await _initializeSettings();
    if (_libraryDensity != density) {
      _libraryDensity = density;
      await _settingsService!.setLibraryDensity(density);
      notifyListeners();
    }
  }

  /// 设置库的视图模式并持久化
  Future<void> setViewMode(ViewMode mode) async {
    if (!_isInitialized) await _initializeSettings();
    if (_viewMode != mode) {
      _viewMode = mode;
      await _settingsService!.setViewMode(mode);
      notifyListeners();
    }
  }

  /// 设置是否使用季级海报并持久化
  Future<void> setUseSeasonPoster(bool value) async {
    if (!_isInitialized) await _initializeSettings();
    if (_useSeasonPoster != value) {
      _useSeasonPoster = value;
      await _settingsService!.setUseSeasonPoster(value);
      notifyListeners();
    }
  }

  /// 设置是否显示英雄展示区并持久化
  Future<void> setShowHeroSection(bool value) async {
    if (!_isInitialized) await _initializeSettings();
    if (_showHeroSection != value) {
      _showHeroSection = value;
      await _settingsService!.setShowHeroSection(value);
      notifyListeners();
    }
  }

  /// 获取库显示密度的本地化显示名称
  String get libraryDensityDisplayName {
    switch (_libraryDensity) {
      case LibraryDensity.compact:
        return '紧凑';
      case LibraryDensity.normal:
        return '正常';
      case LibraryDensity.comfortable:
        return '宽松';
    }
  }
}
