import 'package:package_info_plus/package_info_plus.dart';

/// Plex 客户端配置模型
class PlexConfig {
  /// 服务器基础 URL
  final String baseUrl;
  /// 身份验证令牌
  final String? token;
  /// 客户端唯一标识符
  final String clientIdentifier;
  /// 产品名称（例如：Plezy）
  final String product;
  /// 版本号
  final String version;
  /// 平台名称
  final String platform;
  /// 设备名称
  final String? device;
  /// 是否接受 JSON 响应
  final bool acceptJson;
  /// 服务器机器标识符
  final String? machineIdentifier;

  PlexConfig({
    required this.baseUrl,
    this.token,
    required this.clientIdentifier,
    required this.product,
    required this.version,
    this.platform = 'Flutter',
    this.device,
    this.acceptJson = true,
    this.machineIdentifier,
  });

  /// 创建一个新的 PlexConfig 实例
  /// 自动从平台获取版本号
  static Future<PlexConfig> create({
    required String baseUrl,
    String? token,
    required String clientIdentifier,
    String? product,
    String? platform,
    String? device,
    bool acceptJson = true,
    String? machineIdentifier,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    return PlexConfig(
      baseUrl: baseUrl,
      token: token,
      clientIdentifier: clientIdentifier,
      product: product ?? 'Plezy',
      version: packageInfo.version,
      platform: platform ?? 'Flutter',
      device: device,
      acceptJson: acceptJson,
      machineIdentifier: machineIdentifier,
    );
  }

  /// 获取用于 API 请求的 HTTP 请求头
  Map<String, String> get headers {
    final headers = {
      'X-Plex-Client-Identifier': clientIdentifier,
      'X-Plex-Product': product,
      'X-Plex-Version': version,
      'X-Plex-Platform': platform,
      'X-Plex-Client-Profile-Name': 'Generic',
      if (device != null) 'X-Plex-Device': device!,
      if (acceptJson) 'Accept': 'application/json',
      'Accept-Charset': 'utf-8',
    };

    if (token != null) {
      headers['X-Plex-Token'] = token!;
    }

    return headers;
  }

  PlexConfig copyWith({
    String? baseUrl,
    String? token,
    String? clientIdentifier,
    String? product,
    String? version,
    String? platform,
    String? device,
    bool? acceptJson,
    String? machineIdentifier,
  }) {
    return PlexConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      token: token ?? this.token,
      clientIdentifier: clientIdentifier ?? this.clientIdentifier,
      product: product ?? this.product,
      version: version ?? this.version,
      platform: platform ?? this.platform,
      device: device ?? this.device,
      acceptJson: acceptJson ?? this.acceptJson,
      machineIdentifier: machineIdentifier ?? this.machineIdentifier,
    );
  }
}
