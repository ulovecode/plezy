import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/plex_client.dart';
import '../utils/app_logger.dart';
import '../utils/provider_extensions.dart';
import '../utils/platform_detector.dart';
import '../utils/video_player_navigation.dart';
import '../main.dart';
import '../mixins/refreshable.dart';
import '../navigation/navigation_tabs.dart';
import '../providers/multi_server_provider.dart';
import '../providers/server_state_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/playback_state_provider.dart';
import '../services/offline_watch_sync_service.dart';
import '../providers/offline_mode_provider.dart';
import '../services/plex_auth_service.dart';
import '../services/storage_service.dart';
import '../utils/desktop_window_padding.dart';
import '../widgets/side_navigation_rail.dart';
import 'discover_screen.dart';
import 'libraries/libraries_screen.dart';
import 'search_screen.dart';
import 'downloads/downloads_screen.dart';
import 'settings/settings_screen.dart';
import 'video_player_screen.dart';
import '../watch_together/watch_together.dart';

/// 为主屏幕提供焦点控制的 InheritedWidget。
/// 在 TV 或桌面端，用户需要在侧边栏和主内容区之间切换焦点。
/// 通过这个 Scope，子组件可以方便地请求焦点切换或查询当前焦点状态。
class MainScreenFocusScope extends InheritedWidget {
  final VoidCallback focusSidebar;
  final VoidCallback focusContent;
  final bool isSidebarFocused;

  const MainScreenFocusScope({
    super.key,
    required this.focusSidebar,
    required this.focusContent,
    required this.isSidebarFocused,
    required super.child,
  });

  static MainScreenFocusScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MainScreenFocusScope>();
  }

  @override
  bool updateShouldNotify(MainScreenFocusScope oldWidget) {
    return isSidebarFocused != oldWidget.isSidebarFocused;
  }
}

class MainScreen extends StatefulWidget {
  final PlexClient? client;
  final bool isOfflineMode;

  const MainScreen({super.key, this.client, this.isOfflineMode = false});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with RouteAware {
  late int _currentIndex;
  String? _selectedLibraryGlobalKey;

  /// 应用是否处于离线模式（无法连接到任何服务器）。
  bool _isOffline = false;

  /// 上一次在线时的标签页 ID。
  /// 当应用从离线恢复到在线时，我们希望自动回到用户之前浏览的页面。
  NavigationTabId? _lastOnlineTabId;

  /// 是否因为之前的标签页在离线模式下不可用而自动切换到了“下载”页。
  bool _autoSwitchedToDownloads = false;

  OfflineModeProvider? _offlineModeProvider;

  late List<Widget> _screens;
  // 使用 GlobalKey 来保持各个页面的状态（如滚动位置），即使它们在 IndexedStack 中不处于活动状态。
  final GlobalKey<State<DiscoverScreen>> _discoverKey = GlobalKey();
  final GlobalKey<State<LibrariesScreen>> _librariesKey = GlobalKey();
  final GlobalKey<State<SearchScreen>> _searchKey = GlobalKey();
  final GlobalKey<State<DownloadsScreen>> _downloadsKey = GlobalKey();
  final GlobalKey<State<SettingsScreen>> _settingsKey = GlobalKey();
  final GlobalKey<SideNavigationRailState> _sideNavKey = GlobalKey();

  // 焦点管理：分别管理侧边栏和内容区的焦点范围。
  final FocusScopeNode _sidebarFocusScope = FocusScopeNode(debugLabel: 'Sidebar');
  final FocusScopeNode _contentFocusScope = FocusScopeNode(debugLabel: 'Content');
  bool _isSidebarFocused = false;

  @override
  void initState() {
    super.initState();
    _isOffline = widget.isOfflineMode;

    // 如果处于离线模式，初始索引设为 0（对应离线模式下的下载页）。
    _currentIndex = _isOffline ? 0 : 0;
    _lastOnlineTabId = _isOffline ? null : NavigationTabId.discover;
    _autoSwitchedToDownloads = _isOffline;

    _screens = _buildScreens(_isOffline);

    // 立即设置 Watch Together 回调。
    // 这必须是同步的，以确保能捕获到启动时可能已经存在的早期消息。
    if (!_isOffline) {
      _setupWatchTogetherCallback();
    }

    // 在第一帧渲染后执行初始化逻辑。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_isOffline) {
        // 确保 UserProfileProvider 已就绪。
        final userProfileProvider = context.userProfile;
        await userProfileProvider.initialize();

        // 设置配置切换时的回调，用于清理所有页面的旧数据。
        userProfileProvider.setDataInvalidationCallback(_invalidateAllScreens);
      }

      // 初始焦点分配给内容区，除非侧边栏已被明确激活。
      if (!_isSidebarFocused) {
        _contentFocusScope.requestFocus();
      }
    });
  }

  /// 为“一起看（Watch Together）”设置导航回调。
  void _setupWatchTogetherCallback() {
    try {
      final watchTogether = context.read<WatchTogetherProvider>();
      // 当房主切换影片时，所有成员应同步跳转。
      watchTogether.onMediaSwitched = (ratingKey, serverId, mediaTitle) async {
        appLogger.d('WatchTogether: Media switch received - navigating to $mediaTitle');
        await _navigateToWatchTogetherMedia(ratingKey, serverId);
      };
      // 当房主退出播放器时，为了同步体验，宾客也应自动退出。
      watchTogether.onHostExitedPlayer = () {
        appLogger.d('WatchTogether: Host exited player - exiting player for guest');
        if (!mounted) return;
        final navigator = Navigator.of(context, rootNavigator: true);
        bool isVideoPlayerOnTop = false;
        navigator.popUntil((route) {
          if (route.isCurrent) {
            isVideoPlayerOnTop = route.settings.name == kVideoPlayerRouteName;
          }
          return true;
        });
        if (isVideoPlayerOnTop && navigator.canPop()) {
          navigator.pop();
        }
      };
    } catch (e) {
      appLogger.w('Could not set up Watch Together callback', error: e);
    }
  }

  /// 当房主在“一起看”会话中切换内容时，导航到相应的媒体页面。
  Future<void> _navigateToWatchTogetherMedia(String ratingKey, String serverId) async {
    if (!mounted) return;

    try {
      final multiServer = context.read<MultiServerProvider>();
      final client = multiServer.getClientForServer(serverId);

      if (client == null) {
        appLogger.w('WatchTogether: Server $serverId not available');
        return;
      }

      // 获取新媒体的元数据。
      final metadata = await client.getMetadataWithImages(ratingKey);

      if (metadata == null || !mounted) return;

      // 使用 push 将播放器推入栈中，保持 WatchTogetherScreen 在背景中，
      // 这样用户退出播放后能回到会话控制界面。
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: kVideoPlayerRouteName),
          builder: (_) => VideoPlayerScreen(metadata: metadata),
        ),
      );
    } catch (e) {
      appLogger.e('WatchTogether: Failed to navigate to media', error: e);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 监听离线/在线状态转换。
    // 我们不直接使用 initState 中的状态，因为 Provider 的状态可能在异步加载中发生变化。
    final provider = context.read<OfflineModeProvider?>();
    if (provider != null && provider != _offlineModeProvider) {
      _offlineModeProvider?.removeListener(_handleOfflineStatusChanged);
      _offlineModeProvider = provider;
      _offlineModeProvider!.addListener(_handleOfflineStatusChanged);
    }

    // 注册导航观察者。
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _offlineModeProvider?.removeListener(_handleOfflineStatusChanged);
    _sidebarFocusScope.dispose();
    _contentFocusScope.dispose();
    super.dispose();
  }

  List<Widget> _buildScreens(bool offline) {
    // 离线模式下，隐藏依赖网络的内容（发现、库、搜索），仅保留下载和设置。
    if (offline) {
      return [DownloadsScreen(key: _downloadsKey), SettingsScreen(key: _settingsKey)];
    }

    return [
      DiscoverScreen(key: _discoverKey, onBecameVisible: _onDiscoverBecameVisible),
      LibrariesScreen(key: _librariesKey, onLibraryOrderChanged: _onLibraryOrderChanged),
      SearchScreen(key: _searchKey),
      DownloadsScreen(key: _downloadsKey),
      SettingsScreen(key: _settingsKey),
    ];
  }

  /// 在离线/在线模式切换时，规范化当前的标签页索引。
  /// 如果当前选中的标签在目标模式下仍然存在，则保留它；否则重置到第一个标签。
  int _normalizeIndexForMode(int currentIndex, bool wasOffline, bool isOffline) {
    if (wasOffline == isOffline) return currentIndex;

    final oldTabs = _getVisibleTabs(wasOffline);
    final newTabs = _getVisibleTabs(isOffline);

    final currentTabId = currentIndex >= 0 && currentIndex < oldTabs.length
        ? oldTabs[currentIndex].id
        : oldTabs.first.id;

    final newIndex = newTabs.indexWhere((tab) => tab.id == currentTabId);
    return newIndex >= 0 ? newIndex : 0;
  }

  void _handleOfflineStatusChanged() {
    final newOffline = _offlineModeProvider?.isOffline ?? widget.isOfflineMode;

    if (newOffline == _isOffline) return;

    final previousTabId = _tabIdForIndex(_isOffline, _currentIndex);
    final wasOffline = _isOffline;
    setState(() {
      _isOffline = newOffline;
      _screens = _buildScreens(_isOffline);
      _selectedLibraryGlobalKey = _isOffline ? null : _selectedLibraryGlobalKey;

      if (_isOffline) {
        // 记录在线时的标签，以便重连后恢复。
        if (!wasOffline) {
          _lastOnlineTabId = previousTabId;
        }

        _currentIndex = _normalizeIndexForMode(_currentIndex, wasOffline, _isOffline);

        // 标记是否被迫切换到了下载页。
        _autoSwitchedToDownloads =
            previousTabId != NavigationTabId.downloads &&
            _tabIdForIndex(true, _currentIndex) == NavigationTabId.downloads;
      } else {
        // 恢复在线：如果之前是自动跳到下载页的，现在跳回之前的在线页面。
        if (_autoSwitchedToDownloads) {
          final restoredTab = _lastOnlineTabId ?? NavigationTabId.discover;
          final restoredIndex = NavigationTab.indexFor(restoredTab, isOffline: _isOffline);
          _currentIndex = restoredIndex >= 0 ? restoredIndex : 0;
        } else {
          _currentIndex = _normalizeIndexForMode(_currentIndex, wasOffline, _isOffline);
        }
        _autoSwitchedToDownloads = false;
      }
    });

    // 重新构建导航后，刷新焦点。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sideNavKey.currentState?.focusActiveItem();
    });

    // 恢复在线时重新初始化用户配置。
    if (!_isOffline) {
      final userProfileProvider = context.userProfile;
      userProfileProvider.initialize().then((_) {
        userProfileProvider.setDataInvalidationCallback(_invalidateAllScreens);
      });
    }
  }

  void _focusSidebar() {
    setState(() => _isSidebarFocused = true);
    _sidebarFocusScope.requestFocus();
    // 确保侧边栏获得焦点后，高亮显示当前的活动项。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sideNavKey.currentState?.focusActiveItem();
    });
  }

  void _focusContent() {
    setState(() => _isSidebarFocused = false);
    _contentFocusScope.requestFocus();
    // 如果是在“媒体库”页面，内容区获得焦点时应尝试聚焦到活动标签页。
    if (_currentIndex == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_librariesKey.currentState case final FocusableTab focusable) {
          focusable.focusActiveTabIfReady();
        }
      });
    }
  }

  KeyEventResult _handleBackKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // 处理后退键（Esc、手柄 B 键等）。
    // 这个处理器只有在子组件没有拦截后退键时才会被触发。
    final isBackKey =
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack ||
        event.logicalKey == LogicalKeyboardKey.gameButtonB;

    if (!isBackKey) return KeyEventResult.ignored;

    // 快捷操作：在侧边栏和内容区之间快速切换焦点。
    if (_isSidebarFocused) {
      _focusContent();
    } else {
      _focusSidebar();
    }
    return KeyEventResult.handled;
  }

  @override
  void didPush() {
    // Called when this route has been pushed (initial navigation)
    if (_currentIndex == 0 && !_isOffline) {
      _onDiscoverBecameVisible();
    }
  }

  @override
  void didPopNext() {
    // Called when returning to this route from a child route (e.g., from video player)
    if (_currentIndex == 0 && !_isOffline) {
      _onDiscoverBecameVisible();
    }
  }

  void _onDiscoverBecameVisible() {
    appLogger.d('Navigated to home');
    // Refresh content when returning to discover page
    final discoverState = _discoverKey.currentState;
    if (discoverState != null && discoverState is Refreshable) {
      (discoverState as Refreshable).refresh();
    }
  }

  void _onLibraryOrderChanged() {
    // Refresh side navigation when library order changes
    _sideNavKey.currentState?.reloadLibraries();
  }

  /// Invalidate all cached data across all screens when profile is switched
  /// Receives the list of servers with new profile tokens for reconnection
  Future<void> _invalidateAllScreens(List<PlexServer> servers) async {
    appLogger.d('Invalidating all screen data due to profile switch with ${servers.length} servers');

    // Get all providers
    final multiServerProvider = context.read<MultiServerProvider>();
    final serverStateProvider = context.read<ServerStateProvider>();
    final hiddenLibrariesProvider = context.read<HiddenLibrariesProvider>();
    final playbackStateProvider = context.read<PlaybackStateProvider>();

    // Reconnect to all servers with new profile tokens
    if (servers.isNotEmpty) {
      final storage = await StorageService.getInstance();
      final clientId = storage.getClientIdentifier();

      final connectedCount = await multiServerProvider.reconnectWithServers(servers, clientIdentifier: clientId);
      appLogger.d('Reconnected to $connectedCount/${servers.length} servers after profile switch');

      // Trigger watch state sync now that servers are connected
      if (connectedCount > 0) {
        if (!mounted) return;
        context.read<OfflineWatchSyncService>().onServersConnected();
      }
    }

    // Reset other provider states
    serverStateProvider.reset();
    hiddenLibrariesProvider.refresh();
    playbackStateProvider.clearShuffle();

    appLogger.d('Cleared all provider states for profile switch');

    // Full refresh discover screen (reload all content for new profile)
    if (_discoverKey.currentState case final FullRefreshable refreshable) {
      refreshable.fullRefresh();
    }

    // Full refresh libraries screen (clear filters and reload for new profile)
    if (_librariesKey.currentState case final FullRefreshable refreshable) {
      refreshable.fullRefresh();
    }

    // Full refresh search screen (clear search for new profile)
    if (_searchKey.currentState case final FullRefreshable refreshable) {
      refreshable.fullRefresh();
    }
  }

  void _selectTab(int index) {
    final previousIndex = _currentIndex;
    setState(() {
      _currentIndex = index;
      if (!_isOffline) {
        _lastOnlineTabId = _tabIdForIndex(false, index);
      } else if (previousIndex != index) {
        // User made an explicit offline selection, so don't auto-restore later.
        _autoSwitchedToDownloads = false;
      }
    });

    // Skip screen-specific logic in offline mode (only Downloads and Settings available)
    if (_isOffline) return;

    // Notify discover screen when it becomes visible via tab switch
    if (index == 0) {
      _onDiscoverBecameVisible();
    }
    // Ensure the libraries screen applies focus when brought into view
    if (index == 1 && previousIndex != 1) {
      if (_librariesKey.currentState case final FocusableTab focusable) {
        focusable.focusActiveTabIfReady();
      }
    }
    // Focus search input when selecting Search tab
    if (index == 2) {
      if (_searchKey.currentState case final SearchInputFocusable searchable) {
        searchable.focusSearchInput();
      }
    }
  }

  /// Handle library selection from side navigation rail
  void _selectLibrary(String libraryGlobalKey) {
    setState(() {
      _selectedLibraryGlobalKey = libraryGlobalKey;
      _currentIndex = 1; // Switch to Libraries tab
      if (!_isOffline) {
        _lastOnlineTabId = NavigationTabId.libraries;
      }
    });
    // Tell LibrariesScreen to load this library
    if (_librariesKey.currentState case final LibraryLoadable loadable) {
      loadable.loadLibraryByKey(libraryGlobalKey);
    }
    if (_librariesKey.currentState case final FocusableTab focusable) {
      focusable.focusActiveTabIfReady();
    }
  }

  /// Get navigation tabs filtered by offline mode
  List<NavigationTab> _getVisibleTabs(bool isOffline) {
    return NavigationTab.getVisibleTabs(isOffline: isOffline);
  }

  /// Get the tab ID for a given index, clamping to the available range.
  NavigationTabId _tabIdForIndex(bool isOffline, int index) {
    final tabs = _getVisibleTabs(isOffline);
    if (tabs.isEmpty) return NavigationTabId.discover;
    final safeIndex = index.clamp(0, tabs.length - 1).toInt();
    return tabs[safeIndex].id;
  }

  /// Build navigation destinations for bottom navigation bar.
  List<NavigationDestination> _buildNavDestinations(bool isOffline) {
    return _getVisibleTabs(isOffline).map((tab) => tab.toDestination()).toList();
  }

  @override
  Widget build(BuildContext context) {
    final useSideNav = PlatformDetector.shouldUseSideNavigation(context);

    if (useSideNav) {
      return PopScope(
        canPop: false, // Prevent system back from popping on Android TV
        onPopInvokedWithResult: (didPop, result) {
          // No-op: back key events bubble through widget tree and are handled
          // by content screens (e.g., LibrariesScreen) or MainScreen's _handleBackKey.
          // We only use PopScope to prevent the system from popping the route.
        },
        child: Focus(
          onKeyEvent: (node, event) => _handleBackKey(event),
          child: MainScreenFocusScope(
            focusSidebar: _focusSidebar,
            focusContent: _focusContent,
            isSidebarFocused: _isSidebarFocused,
            child: SideNavigationScope(
              child: Row(
                children: [
                  FocusScope(
                    node: _sidebarFocusScope,
                    child: SideNavigationRail(
                      key: _sideNavKey,
                      selectedIndex: _currentIndex,
                      selectedLibraryKey: _selectedLibraryGlobalKey,
                      isOfflineMode: _isOffline,
                      onDestinationSelected: (index) {
                        _selectTab(index);
                        _focusContent();
                      },
                      onLibrarySelected: (key) {
                        _selectLibrary(key);
                        _focusContent();
                      },
                    ),
                  ),
                  Expanded(
                    child: FocusScope(
                      node: _contentFocusScope,
                      // No autofocus - we control focus programmatically to prevent
                      // autofocus from stealing focus back after setState() rebuilds
                      child: IndexedStack(index: _currentIndex, children: _screens),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        destinations: _buildNavDestinations(_isOffline),
      ),
    );
  }
}
