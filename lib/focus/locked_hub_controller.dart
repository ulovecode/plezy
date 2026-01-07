/// 管理 Hub 导航的焦点记忆。
///
/// 跟踪两件事：
/// 1. 每个 Hub 的记忆：每个 Hub 记录上次聚焦的项目
/// 2. 全局列提示：当进入一个尚未访问过的 Hub 时，
///    我们使用上次聚焦 Hub 的列位置作为提示。
class HubFocusMemory {
  static final Map<String, int> _perHubMemory = {};
  static int _lastColumnHint = 0;

  /// 记录特定 Hub 的聚焦索引。
  static void setForHub(String hubKey, int index) {
    _perHubMemory[hubKey] = index;
    _lastColumnHint = index;
  }

  /// 获取 Hub 的记忆索引，如果没有则回退到列提示。
  static int getForHub(String hubKey, int itemCount) {
    if (itemCount <= 0) return 0;

    // 如果此 Hub 有记忆，则使用它
    if (_perHubMemory.containsKey(hubKey)) {
      return _perHubMemory[hubKey]!.clamp(0, itemCount - 1);
    }

    // 否则使用上次的列提示（限制在此 Hub 的项目数范围内）
    return _lastColumnHint.clamp(0, itemCount - 1);
  }

  /// 清除所有记忆（例如离开屏幕时）。
  static void clear() {
    _perHubMemory.clear();
    _lastColumnHint = 0;
  }
}
