import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import 'grid_size_calculator.dart';
import 'layout_constants.dart';

/// 构建一个自适应 Sliver 组件，根据当前的视图模式设置在网格和列表之间切换。
///
/// 此辅助方法整合了列表与网格的 Sliver 构建器，以保持不同屏幕上的内边距和密度逻辑同步。
Widget buildAdaptiveMediaSliverBuilder<T>({
  required BuildContext context,
  required List<T> items,
  required Widget Function(BuildContext context, T item, int index) itemBuilder,
  required ViewMode viewMode,
  required LibraryDensity density,
  EdgeInsets? padding,
  double? childAspectRatio,
  double? crossAxisSpacing,
  double? mainAxisSpacing,
}) {
  final effectivePadding = padding ?? GridLayoutConstants.gridPadding;
  final effectiveAspectRatio = childAspectRatio ?? GridLayoutConstants.posterAspectRatio;
  final effectiveCrossAxisSpacing = crossAxisSpacing ?? GridLayoutConstants.crossAxisSpacing;
  final effectiveMainAxisSpacing = mainAxisSpacing ?? GridLayoutConstants.mainAxisSpacing;

  if (viewMode == ViewMode.list) {
    return SliverPadding(
      padding: effectivePadding,
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          return itemBuilder(context, item, index);
        }, childCount: items.length),
      ),
    );
  } else {
    return SliverPadding(
      padding: effectivePadding,
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: GridSizeCalculator.getMaxCrossAxisExtent(context, density),
          childAspectRatio: effectiveAspectRatio,
          crossAxisSpacing: effectiveCrossAxisSpacing,
          mainAxisSpacing: effectiveMainAxisSpacing,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          return itemBuilder(context, item, index);
        }, childCount: items.length),
      ),
    );
  }
}
