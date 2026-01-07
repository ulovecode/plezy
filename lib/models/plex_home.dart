import 'plex_home_user.dart';

/// Plex Home（家庭组）模型
class PlexHome {
  /// 家庭组 ID
  final int id;
  /// 家庭组名称
  final String name;
  /// 访客用户 ID
  final int? guestUserID;
  /// 访客用户 UUID
  final String guestUserUUID;
  /// 是否启用访客
  final bool guestEnabled;
  /// 是否有订阅
  final bool subscription;
  /// 家庭组内的用户列表
  final List<PlexHomeUser> users;

  PlexHome({
    required this.id,
    required this.name,
    required this.guestUserID,
    required this.guestUserUUID,
    required this.guestEnabled,
    required this.subscription,
    required this.users,
  });

  factory PlexHome.fromJson(Map<String, dynamic> json) {
    final List<dynamic> usersJson = json['users'] as List<dynamic>;
    final users = usersJson.map((userJson) => PlexHomeUser.fromJson(userJson as Map<String, dynamic>)).toList();

    return PlexHome(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String,
      guestUserID: (json['guestUserID'] as num?)?.toInt(),
      guestUserUUID: json['guestUserUUID'] as String,
      guestEnabled: json['guestEnabled'] as bool,
      subscription: json['subscription'] as bool,
      users: users,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'guestUserID': guestUserID,
      'guestUserUUID': guestUserUUID,
      'guestEnabled': guestEnabled,
      'subscription': subscription,
      'users': users.map((user) => user.toJson()).toList(),
    };
  }

  /// 获取管理员用户
  PlexHomeUser? get adminUser => users.where((user) => user.admin).firstOrNull;

  /// 获取托管用户列表（非管理员）
  List<PlexHomeUser> get managedUsers => users.where((user) => !user.admin).toList();

  /// 获取受限用户列表
  List<PlexHomeUser> get restrictedUsers => users.where((user) => user.restricted).toList();

  /// 根据 UUID 获取用户
  PlexHomeUser? getUserByUUID(String uuid) {
    try {
      return users.firstWhere((user) => user.uuid == uuid);
    } catch (e) {
      return null;
    }
  }

  /// 检查是否有多个用户
  bool get hasMultipleUsers => users.length > 1;
}
