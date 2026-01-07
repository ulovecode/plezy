import 'package:flutter/material.dart';

/// 为库标签页（Library Tabs）提供焦点管理的混入（Mixin）。
/// 处理第一个项目的焦点节点生命周期，并提供一个在该项目上请求焦点的方法。
mixin LibraryTabFocusMixin<T extends StatefulWidget> on State<T> {
  /// 第一个项目的焦点节点（用于程序化聚焦）
  late final FocusNode firstItemFocusNode;

  /// 焦点节点的调试标签
  String get focusNodeDebugLabel;

  /// 列表/网格中的项目数量
  int get itemCount;

  @override
  void initState() {
    super.initState();
    firstItemFocusNode = FocusNode(debugLabel: focusNodeDebugLabel);
  }

  @override
  void dispose() {
    firstItemFocusNode.dispose();
    super.dispose();
  }

  /// 聚焦网格/列表中的第一个项目（用于标签页激活时）
  void focusFirstItem() {
    if (itemCount > 0) {
      firstItemFocusNode.requestFocus();
    }
  }
}
