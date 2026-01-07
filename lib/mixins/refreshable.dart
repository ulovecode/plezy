mixin Refreshable {
  void refresh();
}

/// 支持完整刷新（清除所有缓存数据）的屏幕所使用的混入（Mixin）
mixin FullRefreshable {
  void fullRefresh();
}

/// 具有可聚焦标签页内容的屏幕所使用的混入（Mixin）
mixin FocusableTab {
  void focusActiveTabIfReady();
}

/// 具有可聚焦搜索输入框的屏幕所使用的混入（Mixin）
mixin SearchInputFocusable {
  void focusSearchInput();
}

/// 可以根据 Key 加载特定库的屏幕所使用的混入（Mixin）
mixin LibraryLoadable {
  void loadLibraryByKey(String libraryGlobalKey);
}
