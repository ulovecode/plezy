import 'package:flutter/material.dart';
import '../services/plex_client.dart';
import '../models/plex_metadata.dart';

/// 在观看状态改变后需要更新单个项目的屏幕所使用的混入（Mixin）。
///
/// 这为获取更新的元数据和替换列表中的项目提供了标准实现，
/// 同时允许每个屏幕自定义应更新哪些列表。
mixin ItemUpdatable<T extends StatefulWidget> on State<T> {
  /// 用于获取更新元数据的 Plex 客户端。
  /// 每个屏幕必须提供对其客户端的访问。
  PlexClient get client;

  /// 在观看状态改变后更新屏幕列表中的单个项目。
  ///
  /// 获取包含图像（包括 clearLogo）的最新元数据，
  /// 并调用 [updateItemInLists] 来更新相应的列表。
  ///
  /// 如果获取失败，错误将被静默捕获，该项目将在下次完整刷新时更新。
  Future<void> updateItem(String ratingKey) async {
    try {
      final updatedMetadata = await client.getMetadataWithImages(ratingKey);
      if (updatedMetadata != null) {
        setState(() {
          updateItemInLists(ratingKey, updatedMetadata);
        });
      }
    } catch (e) {
      // 静默失败 - 该项目将在下次完整刷新时更新
    }
  }

  /// 重写此方法以指定应更新哪些列表。
  ///
  /// 此方法在 [setState] 内部调用，因此你应该直接修改列表，
  /// 而无需再次调用 setState。
  ///
  /// 示例：
  /// ```dart
  /// @override
  /// void updateItemInLists(String ratingKey, PlexMetadata updatedMetadata) {
  ///   final index = _items.indexWhere((item) => item.ratingKey == ratingKey);
  ///   if (index != -1) {
  ///     _items[index] = updatedMetadata;
  ///   }
  /// }
  /// ```
  void updateItemInLists(String ratingKey, PlexMetadata updatedMetadata);
}
