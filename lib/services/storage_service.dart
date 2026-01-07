import 'dart:convert';

import '../utils/log_redaction_manager.dart';
import 'base_shared_preferences_service.dart';

/// 存储服务，继承自 BaseSharedPreferencesService，用于管理应用的所有持久化配置和数据。
class StorageService extends BaseSharedPreferencesService {
  // 存储键名常量
  static const String _keyServerUrl = 'server_url';
  static const String _keyToken = 'token';
  static const String _keyPlexToken = 'plex_token';
  static const String _keyServerData = 'server_data';
  static const String _keyClientId = 'client_identifier';
  static const String _keySelectedLibraryIndex = 'selected_library_index';
  static const String _keySelectedLibraryKey = 'selected_library_key';
  static const String _keyLibraryFilters = 'library_filters';
  static const String _keyLibraryOrder = 'library_order';
  static const String _keyUserProfile = 'user_profile';
  static const String _keyCurrentUserUUID = 'current_user_uuid';
  static const String _keyHomeUsersCache = 'home_users_cache';
  static const String _keyHomeUsersCacheExpiry = 'home_users_cache_expiry';
  static const String _keyHiddenLibraries = 'hidden_libraries';
  static const String _keyServersList = 'servers_list';
  static const String _keyServerOrder = 'server_order';

  // 用于按 ID 存储的键名前缀
  static const String _prefixServerEndpoint = 'server_endpoint_';
  static const String _prefixLibraryFilters = 'library_filters_';
  static const String _prefixLibrarySort = 'library_sort_';
  static const String _prefixLibraryGrouping = 'library_grouping_';
  static const String _prefixLibraryTab = 'library_tab_';

  // 用于批量清理的键名分组
  static const List<String> _credentialKeys = [
    _keyServerUrl,
    _keyToken,
    _keyPlexToken,
    _keyServerData,
    _keyClientId,
    _keyUserProfile,
    _keyCurrentUserUUID,
    _keyHomeUsersCache,
    _keyHomeUsersCacheExpiry,
  ];

  static const List<String> _libraryPreferenceKeys = [
    _keySelectedLibraryIndex,
    _keyLibraryFilters,
    _keyLibraryOrder,
    _keyHiddenLibraries,
  ];

  StorageService._();

  /// 获取 StorageService 单例
  static Future<StorageService> getInstance() async {
    return BaseSharedPreferencesService.initializeInstance(() => StorageService._());
  }

  @override
  Future<void> onInit() async {
    // 初始化时注册已知值，以便日志能够立即脱敏
    LogRedactionManager.registerServerUrl(getServerUrl());
    LogRedactionManager.registerToken(getToken());
    LogRedactionManager.registerToken(getPlexToken());
  }

  // 服务器 URL 管理
  /// 保存服务器 URL
  Future<void> saveServerUrl(String url) async {
    await prefs.setString(_keyServerUrl, url);
    LogRedactionManager.registerServerUrl(url);
  }

  /// 获取保存的服务器 URL
  String? getServerUrl() {
    return prefs.getString(_keyServerUrl);
  }

  // 特定服务器的端点 URL（用于多服务器连接缓存）
  /// 保存特定服务器的端点 URL
  Future<void> saveServerEndpoint(String serverId, String url) async {
    await prefs.setString('$_prefixServerEndpoint$serverId', url);
    LogRedactionManager.registerServerUrl(url);
  }

  /// 获取特定服务器的端点 URL
  String? getServerEndpoint(String serverId) {
    return prefs.getString('$_prefixServerEndpoint$serverId');
  }

  /// 清除特定服务器的端点 URL
  Future<void> clearServerEndpoint(String serverId) async {
    await prefs.remove('$_prefixServerEndpoint$serverId');
  }

  // 服务器访问令牌 (Access Token)
  /// 保存服务器令牌
  Future<void> saveToken(String token) async {
    await prefs.setString(_keyToken, token);
    LogRedactionManager.registerToken(token);
  }

  /// 获取服务器令牌
  String? getToken() {
    return prefs.getString(_keyToken);
  }

  // 为了清晰起见，提供服务器令牌的别名方法
  /// 保存服务器访问令牌（别名方法）
  Future<void> saveServerAccessToken(String token) async {
    await saveToken(token);
  }

  /// 获取服务器访问令牌（别名方法）
  String? getServerAccessToken() {
    return getToken();
  }

  // Plex.tv 令牌（用于 API 访问）
  /// 保存 Plex.tv 令牌
  Future<void> savePlexToken(String token) async {
    await prefs.setString(_keyPlexToken, token);
    LogRedactionManager.registerToken(token);
  }

  /// 获取 Plex.tv 令牌
  String? getPlexToken() {
    return prefs.getString(_keyPlexToken);
  }

  // 服务器数据（完整的 PlexServer 对象，以 JSON 形式存储）
  /// 保存服务器数据
  Future<void> saveServerData(Map<String, dynamic> serverJson) async {
    await _setJsonMap(_keyServerData, serverJson);
  }

  /// 获取服务器数据
  Map<String, dynamic>? getServerData() {
    return _readJsonMap(_keyServerData);
  }

  // 客户端标识符 (Client Identifier)
  /// 保存客户端标识符
  Future<void> saveClientIdentifier(String clientId) async {
    await prefs.setString(_keyClientId, clientId);
  }

  /// 获取客户端标识符
  String? getClientIdentifier() {
    return prefs.getString(_keyClientId);
  }

  // 一次性保存所有凭据
  /// 保存凭据（服务器 URL、令牌、客户端标识符）
  Future<void> saveCredentials({
    required String serverUrl,
    required String token,
    required String clientIdentifier,
  }) async {
    await Future.wait([saveServerUrl(serverUrl), saveToken(token), saveClientIdentifier(clientIdentifier)]);
  }

  // 检查凭据是否存在
  /// 是否已保存凭据
  bool hasCredentials() {
    return getServerUrl() != null && getToken() != null;
  }

  // 清除所有凭据
  /// 清除所有凭据及相关的多服务器数据
  Future<void> clearCredentials() async {
    await Future.wait([..._credentialKeys.map((k) => prefs.remove(k)), clearMultiServerData()]);
    LogRedactionManager.clearTrackedValues();
  }

  // 以 Map 形式获取所有凭据
  /// 获取所有凭据的 Map
  Map<String, String?> getCredentials() {
    return {'serverUrl': getServerUrl(), 'token': getToken(), 'clientIdentifier': getClientIdentifier()};
  }

  /// 获取选中的媒体库索引
  int? getSelectedLibraryIndex() {
    return prefs.getInt(_keySelectedLibraryIndex);
  }

  // 选中的媒体库 Key（替换基于索引的选择）
  /// 保存选中的媒体库 Key
  Future<void> saveSelectedLibraryKey(String key) async {
    await prefs.setString(_keySelectedLibraryKey, key);
  }

  /// 获取选中的媒体库 Key
  String? getSelectedLibraryKey() {
    return prefs.getString(_keySelectedLibraryKey);
  }

  // 媒体库筛选器（以 JSON 字符串形式存储）
  /// 保存媒体库筛选器
  /// [sectionId] - 可选的媒体库 ID，如果提供则按媒体库存储
  Future<void> saveLibraryFilters(Map<String, String> filters, {String? sectionId}) async {
    final key = sectionId != null ? '$_prefixLibraryFilters$sectionId' : _keyLibraryFilters;
    // 注意：使用 Map<String, String>，json.encode 可以正确处理
    final jsonString = json.encode(filters);
    await prefs.setString(key, jsonString);
  }

  /// 获取媒体库筛选器
  /// [sectionId] - 可选的媒体库 ID
  Map<String, String> getLibraryFilters({String? sectionId}) {
    final scopedKey = sectionId != null ? '$_prefixLibraryFilters$sectionId' : _keyLibraryFilters;

    // 优先获取特定媒体库的筛选器
    final jsonString =
        prefs.getString(scopedKey) ??
        // 兼容性支持：如果不存在，则回退到全局筛选器
        prefs.getString(_keyLibraryFilters);
    if (jsonString == null) return {};

    final decoded = _decodeJsonStringToMap(jsonString);
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  // 媒体库排序（按媒体库存储，包含排序键和降序标志）
  /// 保存媒体库排序设置
  Future<void> saveLibrarySort(String sectionId, String sortKey, {bool descending = false}) async {
    final sortData = {'key': sortKey, 'descending': descending};
    await _setJsonMap('$_prefixLibrarySort$sectionId', sortData);
  }

  /// 获取媒体库排序设置
  Map<String, dynamic>? getLibrarySort(String sectionId) {
    return _readJsonMap('$_prefixLibrarySort$sectionId', legacyStringOk: true);
  }

  // 媒体库分组（按媒体库存储，例如：'movies', 'shows', 'seasons', 'episodes'）
  /// 保存媒体库分组设置
  Future<void> saveLibraryGrouping(String sectionId, String grouping) async {
    await prefs.setString('$_prefixLibraryGrouping$sectionId', grouping);
  }

  /// 获取媒体库分组设置
  String? getLibraryGrouping(String sectionId) {
    return prefs.getString('$_prefixLibraryGrouping$sectionId');
  }

  // 媒体库标签页（按媒体库存储，保存最后选中的标签页索引）
  /// 保存媒体库标签页索引
  Future<void> saveLibraryTab(String sectionId, int tabIndex) async {
    await prefs.setInt('$_prefixLibraryTab$sectionId', tabIndex);
  }

  /// 获取媒体库标签页索引
  int? getLibraryTab(String sectionId) {
    return prefs.getInt('$_prefixLibraryTab$sectionId');
  }

  // 已隐藏的媒体库（以媒体库 section ID 的 JSON 数组形式存储）
  /// 保存已隐藏的媒体库 Key 集合
  Future<void> saveHiddenLibraries(Set<String> libraryKeys) async {
    await _setStringList(_keyHiddenLibraries, libraryKeys.toList());
  }

  /// 获取已隐藏的媒体库 Key 集合
  Set<String> getHiddenLibraries() {
    final jsonString = prefs.getString(_keyHiddenLibraries);
    if (jsonString == null) return {};

    try {
      final list = json.decode(jsonString) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (e) {
      return {};
    }
  }

  // 清除媒体库偏好设置
  /// 清除所有媒体库相关的偏好设置（排序、筛选、分组、标签页等）
  Future<void> clearLibraryPreferences() async {
    await Future.wait([
      ..._libraryPreferenceKeys.map((k) => prefs.remove(k)),
      _clearKeysWithPrefix(_prefixLibrarySort),
      _clearKeysWithPrefix(_prefixLibraryFilters),
      _clearKeysWithPrefix(_prefixLibraryGrouping),
      _clearKeysWithPrefix(_prefixLibraryTab),
    ]);
  }

  // 媒体库排序（以媒体库 Key 的 JSON 列表形式存储）
  /// 保存媒体库顺序
  Future<void> saveLibraryOrder(List<String> libraryKeys) async {
    await _setStringList(_keyLibraryOrder, libraryKeys);
  }

  /// 获取媒体库顺序
  List<String>? getLibraryOrder() => _getStringList(_keyLibraryOrder);

  // 用户资料（以 JSON 字符串形式存储）
  /// 保存用户资料
  Future<void> saveUserProfile(Map<String, dynamic> profileJson) async {
    await _setJsonMap(_keyUserProfile, profileJson);
  }

  /// 获取用户资料
  Map<String, dynamic>? getUserProfile() {
    return _readJsonMap(_keyUserProfile);
  }

  // 当前用户 UUID
  /// 保存当前用户 UUID
  Future<void> saveCurrentUserUUID(String uuid) async {
    await prefs.setString(_keyCurrentUserUUID, uuid);
  }

  /// 获取当前用户 UUID
  String? getCurrentUserUUID() {
    return prefs.getString(_keyCurrentUserUUID);
  }

  // 家庭用户缓存（以带过期时间的 JSON 字符串形式存储）
  /// 保存家庭用户缓存
  Future<void> saveHomeUsersCache(Map<String, dynamic> homeData) async {
    await _setJsonMap(_keyHomeUsersCache, homeData);

    // 设置缓存有效期为 1 小时
    final expiry = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
    await prefs.setInt(_keyHomeUsersCacheExpiry, expiry);
  }

  /// 获取家庭用户缓存
  Map<String, dynamic>? getHomeUsersCache() {
    final expiry = prefs.getInt(_keyHomeUsersCacheExpiry);
    if (expiry == null || DateTime.now().millisecondsSinceEpoch > expiry) {
      // 缓存已过期，清除并返回 null
      clearHomeUsersCache();
      return null;
    }

    return _readJsonMap(_keyHomeUsersCache);
  }

  /// 清除家庭用户缓存
  Future<void> clearHomeUsersCache() async {
    await Future.wait([prefs.remove(_keyHomeUsersCache), prefs.remove(_keyHomeUsersCacheExpiry)]);
  }

  // 清除当前用户 UUID（用于切换服务器）
  /// 清除当前用户 UUID
  Future<void> clearCurrentUserUUID() async {
    await prefs.remove(_keyCurrentUserUUID);
  }

  // 清除所有用户相关数据（用于退出登录）
  /// 清除所有用户数据（凭据和媒体库偏好）
  Future<void> clearUserData() async {
    await Future.wait([clearCredentials(), clearLibraryPreferences()]);
  }

  // 切换后更新当前用户
  /// 更新当前用户信息（UUID 和令牌）
  Future<void> updateCurrentUser(String userUUID, String authToken) async {
    await Future.wait([
      saveCurrentUserUUID(userUUID),
      saveToken(authToken), // 更新主令牌
    ]);
  }

  // 多服务器支持方法

  /// 以 JSON 字符串形式获取服务器列表
  String? getServersListJson() {
    return prefs.getString(_keyServersList);
  }

  /// 以 JSON 字符串形式保存服务器列表
  Future<void> saveServersListJson(String serversJson) async {
    await prefs.setString(_keyServersList, serversJson);
  }

  /// 清除服务器列表
  Future<void> clearServersList() async {
    await prefs.remove(_keyServersList);
  }

  /// 清除所有多服务器数据
  Future<void> clearMultiServerData() async {
    await Future.wait([clearServersList(), clearServerOrder(), _clearKeysWithPrefix(_prefixServerEndpoint)]);
  }

  /// 服务器顺序（以服务器 ID 的 JSON 列表形式存储）
  /// 保存服务器顺序
  Future<void> saveServerOrder(List<String> serverIds) async {
    await _setStringList(_keyServerOrder, serverIds);
  }

  /// 获取服务器顺序
  List<String>? getServerOrder() => _getStringList(_keyServerOrder);

  /// 清除服务器顺序
  Future<void> clearServerOrder() async {
    await prefs.remove(_keyServerOrder);
  }

  // 私有辅助方法

  /// 从偏好设置中读取并解码 JSON `List<String>` 的辅助方法
  List<String>? _getStringList(String key) {
    final jsonString = prefs.getString(key);
    if (jsonString == null) return null;

    try {
      final decoded = json.decode(jsonString) as List<dynamic>;
      return decoded.map((e) => e.toString()).toList();
    } catch (e) {
      return null;
    }
  }

  /// 从偏好设置中读取并解码 JSON Map 的辅助方法
  ///
  /// [key] - 要读取的偏好设置键名
  /// [legacyStringOk] - 如果为 true，当值为普通字符串时，返回 {'key': value, 'descending': false}
  ///                    （用于兼容旧版媒体库排序）
  Map<String, dynamic>? _readJsonMap(String key, {bool legacyStringOk = false}) {
    final jsonString = prefs.getString(key);
    if (jsonString == null) return null;

    return _decodeJsonStringToMap(jsonString, legacyStringOk: legacyStringOk);
  }

  /// 带错误处理的 JSON 字符串转 Map 解码辅助方法
  ///
  /// [jsonString] - 要解码的 JSON 字符串
  /// [legacyStringOk] - 如果为 true，当值为普通字符串时，返回 {'key': value, 'descending': false}
  ///                    （用于兼容旧版媒体库排序）
  Map<String, dynamic> _decodeJsonStringToMap(String jsonString, {bool legacyStringOk = false}) {
    try {
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      if (legacyStringOk) {
        // 兼容性支持：如果只是一个字符串，则将其作为 key 返回
        return {'key': jsonString, 'descending': false};
      }
      return {};
    }
  }

  /// 删除所有以特定前缀开头的键
  Future<void> _clearKeysWithPrefix(String prefix) async {
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix));
    await Future.wait(keys.map((k) => prefs.remove(k)));
  }

  // 公共 JSON 辅助方法，用于减少样板代码

  /// 将可 JSON 编码的 Map 保存到存储中
  Future<void> _setJsonMap(String key, Map<String, dynamic> data) async {
    final jsonString = json.encode(data);
    await prefs.setString(key, jsonString);
  }

  /// 将字符串列表作为 JSON 数组保存
  Future<void> _setStringList(String key, List<String> list) async {
    final jsonString = json.encode(list);
    await prefs.setString(key, jsonString);
  }
}
