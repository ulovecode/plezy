import 'package:shared_preferences/shared_preferences.dart';

/// 使用 SharedPreferences 单例模式的服务基类。
///
/// 该类处理单例初始化和 SharedPreferences 生命周期管理的样板代码。
/// 子类应当：
/// 1. 创建一个私有的命名构造函数（例如：SettingsService._()）
/// 2. 实现自己的 getInstance() 方法，并调用 BaseSharedPreferencesService.initializeInstance()
/// 3. 可选地重写 onInit() 以进行初始化后的设置
abstract class BaseSharedPreferencesService {
  static final Map<Type, BaseSharedPreferencesService> _instances = {};
  late SharedPreferences _prefs;

  /// 供子类使用的受保护构造函数
  BaseSharedPreferencesService();

  /// 访问 SharedPreferences 实例
  SharedPreferences get prefs => _prefs;

  /// 初始化 SharedPreferences 实例
  ///
  /// 该方法处理：
  /// - 单例实例管理
  /// - SharedPreferences 初始化
  /// - 调用 onInit() 钩子进行子类特定的设置
  static Future<T> initializeInstance<T extends BaseSharedPreferencesService>(T Function() constructor) async {
    if (_instances[T] == null) {
      final instance = constructor();
      _instances[T] = instance;
      instance._prefs = await SharedPreferences.getInstance();
      await instance.onInit();
    }
    return _instances[T] as T;
  }

  /// SharedPreferences 准备就绪后，用于子类特定初始化的钩子。
  ///
  /// 重写此方法以执行任何需要访问 SharedPreferences 的设置
  /// （例如：向其他服务注册值）。
  Future<void> onInit() async {
    // 默认实现不执行任何操作
  }
}
