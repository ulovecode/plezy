import 'package:json_annotation/json_annotation.dart';

/// 为模型提供多服务器支持字段的混入（Mixin）。
///
/// 此混入添加了 serverId 和 serverName 字段，这些字段不包含在 JSON 序列化中，
/// 但可用于跟踪项目属于哪个服务器。
mixin MultiServerFields {
  /// 服务器机器标识符（非来自 API）
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? get serverId;

  /// 服务器显示名称（非来自 API）
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? get serverName;
}
