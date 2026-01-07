import 'plex_user_profile.dart';

/// 切换用户后的响应模型
class UserSwitchResponse {
  /// 用户 ID
  final int id;
  /// 用户 UUID
  final String uuid;
  /// 用户名
  final String username;
  /// 用户标题
  final String title;
  /// 用户邮箱
  final String email;
  /// 友好名称
  final String? friendlyName;
  /// 区域语言
  final String? locale;
  /// 是否已确认
  final bool confirmed;
  /// 加入时间（时间戳）
  final int joinedAt;
  /// 是否仅邮箱认证
  final bool emailOnlyAuth;
  /// 是否有密码
  final bool hasPassword;
  /// 是否受保护（通常指有 PIN 码）
  final bool protected;
  /// 头像 URL
  final String thumb;
  /// 认证令牌
  final String authToken;
  /// 邮件列表是否激活
  final bool? mailingListActive;
  /// 记录播放进度的类型
  final String scrobbleTypes;
  /// 国家/地区
  final String country;
  /// 是否受限
  final bool restricted;
  /// 是否匿名
  final bool? anonymous;
  /// 是否属于 Home 组
  final bool home;
  /// 是否是访客
  final bool guest;
  /// Home 组大小
  final int homeSize;
  /// 是否是 Home 管理员
  final bool homeAdmin;
  /// 最大 Home 组大小
  final int maxHomeSize;
  /// 用户个人资料信息
  final PlexUserProfile profile;
  /// 是否启用双重身份验证
  final bool twoFactorEnabled;
  /// 是否已创建备份代码
  final bool backupCodesCreated;
  /// 归属合作伙伴
  final String? attributionPartner;

  UserSwitchResponse({
    required this.id,
    required this.uuid,
    required this.username,
    required this.title,
    required this.email,
    this.friendlyName,
    this.locale,
    required this.confirmed,
    required this.joinedAt,
    required this.emailOnlyAuth,
    required this.hasPassword,
    required this.protected,
    required this.thumb,
    required this.authToken,
    this.mailingListActive,
    required this.scrobbleTypes,
    required this.country,
    required this.restricted,
    this.anonymous,
    required this.home,
    required this.guest,
    required this.homeSize,
    required this.homeAdmin,
    required this.maxHomeSize,
    required this.profile,
    required this.twoFactorEnabled,
    required this.backupCodesCreated,
    this.attributionPartner,
  });

  factory UserSwitchResponse.fromJson(Map<String, dynamic> json) {
    return UserSwitchResponse(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      username: json['username'] as String? ?? '',
      title: json['title'] as String,
      email: json['email'] as String? ?? '',
      friendlyName: json['friendlyName'] as String?,
      locale: json['locale'] as String?,
      confirmed: json['confirmed'] as bool,
      joinedAt: json['joinedAt'] as int,
      emailOnlyAuth: json['emailOnlyAuth'] as bool,
      hasPassword: json['hasPassword'] as bool,
      protected: json['protected'] as bool,
      thumb: json['thumb'] as String,
      authToken: json['authToken'] as String,
      mailingListActive: json['mailingListActive'] as bool?,
      scrobbleTypes: json['scrobbleTypes'] as String? ?? '',
      country: json['country'] as String? ?? '',
      restricted: json['restricted'] as bool,
      anonymous: json['anonymous'] as bool?,
      home: json['home'] as bool,
      guest: json['guest'] as bool,
      homeSize: json['homeSize'] as int,
      homeAdmin: json['homeAdmin'] as bool,
      maxHomeSize: json['maxHomeSize'] as int,
      profile: PlexUserProfile.fromJson(json),
      twoFactorEnabled: json['twoFactorEnabled'] as bool,
      backupCodesCreated: json['backupCodesCreated'] as bool,
      attributionPartner: json['attributionPartner'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'username': username,
      'title': title,
      'email': email,
      'friendlyName': friendlyName,
      'locale': locale,
      'confirmed': confirmed,
      'joinedAt': joinedAt,
      'emailOnlyAuth': emailOnlyAuth,
      'hasPassword': hasPassword,
      'protected': protected,
      'thumb': thumb,
      'authToken': authToken,
      'mailingListActive': mailingListActive,
      'scrobbleTypes': scrobbleTypes,
      'country': country,
      'restricted': restricted,
      'anonymous': anonymous,
      'home': home,
      'guest': guest,
      'homeSize': homeSize,
      'homeAdmin': homeAdmin,
      'maxHomeSize': maxHomeSize,
      'profile': profile.toJson()['profile'],
      'twoFactorEnabled': twoFactorEnabled,
      'backupCodesCreated': backupCodesCreated,
      'attributionPartner': attributionPartner,
    };
  }

  String get displayName => friendlyName ?? title;

  bool get isAdminUser => homeAdmin;
  bool get isRestrictedUser => restricted;
  bool get isGuestUser => guest;
  bool get requiresPassword => hasPassword;
  bool get isSecureUser => twoFactorEnabled || backupCodesCreated;
}
