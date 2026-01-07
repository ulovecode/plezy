/// Plex 家庭组用户模型
class PlexHomeUser {
  /// 用户 ID
  final int id;
  /// 用户唯一标识符
  final String uuid;
  /// 用户标题/名称
  final String title;
  /// 用户名
  final String? username;
  /// 电子邮件
  final String? email;
  /// 友好名称（别名）
  final String? friendlyName;
  /// 头像 URL
  final String thumb;
  /// 是否设置了密码
  final bool hasPassword;
  /// 是否为受限用户
  final bool restricted;
  /// 最后更新时间戳
  final int? updatedAt;
  /// 是否为管理员
  final bool admin;
  /// 是否为访客
  final bool guest;
  /// 是否受保护（需要 PIN 码）
  final bool protected;

  PlexHomeUser({
    required this.id,
    required this.uuid,
    required this.title,
    this.username,
    this.email,
    this.friendlyName,
    required this.thumb,
    required this.hasPassword,
    required this.restricted,
    required this.updatedAt,
    required this.admin,
    required this.guest,
    required this.protected,
  });

  factory PlexHomeUser.fromJson(Map<String, dynamic> json) {
    return PlexHomeUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      uuid: json['uuid'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown',
      username: json['username'] as String?,
      email: json['email'] as String?,
      friendlyName: json['friendlyName'] as String?,
      thumb: json['thumb'] as String? ?? '',
      hasPassword: json['hasPassword'] as bool? ?? false,
      restricted: json['restricted'] as bool? ?? false,
      updatedAt: (json['updatedAt'] as num?)?.toInt(),
      admin: json['admin'] as bool? ?? false,
      guest: json['guest'] as bool? ?? false,
      protected: json['protected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'title': title,
      'username': username,
      'email': email,
      'friendlyName': friendlyName,
      'thumb': thumb,
      'hasPassword': hasPassword,
      'restricted': restricted,
      'updatedAt': updatedAt,
      'admin': admin,
      'guest': guest,
      'protected': protected,
    };
  }

  /// 获取显示的名称
  String get displayName => friendlyName ?? title;

  /// 检查是否为管理员用户
  bool get isAdminUser => admin;
  /// 检查是否为受限用户
  bool get isRestrictedUser => restricted;
  /// 检查是否为访客用户
  bool get isGuestUser => guest;
  /// 检查是否需要密码/PIN 码
  bool get requiresPassword => protected;
}
