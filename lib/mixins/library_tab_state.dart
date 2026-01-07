import 'package:flutter/material.dart';
import '../services/plex_client.dart';
import '../models/plex_library.dart';
import '../utils/provider_extensions.dart';

/// 为库标签页（Library Tab）屏幕提供通用功能的混入（Mixin）。
/// 提供针对特定服务器的客户端解析，以支持多服务器。
mixin LibraryTabStateMixin<T extends StatefulWidget> on State<T> {
  /// 正在显示的库
  PlexLibrary get library;

  /// 获取此库所属服务器的正确 PlexClient
  /// 如果没有可用的客户端，则抛出异常
  PlexClient getClientForLibrary() => context.getClientForLibrary(library);
}
