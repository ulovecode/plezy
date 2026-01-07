import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';

/// 用于在整个应用中管理隐藏库状态的 Provider。
/// 这确保了当一个库在一个屏幕中被隐藏/取消隐藏时，
/// 所有其他屏幕都会自动更新。
class HiddenLibrariesProvider extends ChangeNotifier {
  late StorageService _storageService;
  Set<String> _hiddenLibraryKeys = {};
  bool _isInitialized = false;
  Future<void>? _initFuture;

  HiddenLibrariesProvider() {
    // 尽早开始初始化以减少竞态条件
    _initFuture = _initialize();
  }

  /// 确保 Provider 已初始化。在需要实际持久化值的上下文中
  /// 访问隐藏库之前调用此方法。
  Future<void> ensureInitialized() => _initFuture ?? _initialize();

  /// 检查 Provider 是否已完成初始化
  bool get isInitialized => _isInitialized;

  /// 获取隐藏库键的不可变副本
  Set<String> get hiddenLibraryKeys => Set.unmodifiable(_hiddenLibraryKeys);

  /// 通过从存储加载隐藏库来初始化 Provider
  Future<void> _initialize() async {
    if (_isInitialized) return;
    _storageService = await StorageService.getInstance();
    _hiddenLibraryKeys = _storageService.getHiddenLibraries();
    _isInitialized = true;
    notifyListeners();
  }

  /// 通过键隐藏库
  /// 同时更新内存状态和持久化存储
  Future<void> hideLibrary(String libraryKey) async {
    if (!_isInitialized) await _initialize();
    if (!_hiddenLibraryKeys.contains(libraryKey)) {
      _hiddenLibraryKeys = Set.from(_hiddenLibraryKeys)..add(libraryKey);
      await _storageService.saveHiddenLibraries(_hiddenLibraryKeys);
      notifyListeners();
    }
  }

  /// 通过键取消隐藏库
  /// 同时更新内存状态和持久化存储
  Future<void> unhideLibrary(String libraryKey) async {
    if (!_isInitialized) await _initialize();
    if (_hiddenLibraryKeys.contains(libraryKey)) {
      _hiddenLibraryKeys = Set.from(_hiddenLibraryKeys)..remove(libraryKey);
      await _storageService.saveHiddenLibraries(_hiddenLibraryKeys);
      notifyListeners();
    }
  }

  /// 检查特定库是否已隐藏
  bool isLibraryHidden(String libraryKey) => _hiddenLibraryKeys.contains(libraryKey);

  /// 从存储刷新隐藏库
  /// 如果存储在 Provider 之外被修改，此方法很有用
  Future<void> refresh() async {
    _hiddenLibraryKeys = _storageService.getHiddenLibraries();
    notifyListeners();
  }
}
