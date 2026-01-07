import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/main_screen.dart';
import 'screens/auth_screen.dart';
import 'services/storage_service.dart';
import 'services/macos_titlebar_service.dart';
import 'services/fullscreen_state_manager.dart';
import 'services/update_service.dart';
import 'services/settings_service.dart';
import 'utils/platform_detector.dart';
import 'services/discord_rpc_service.dart';
import 'services/gamepad_service.dart';
import 'providers/user_profile_provider.dart';
import 'providers/plex_client_provider.dart';
import 'providers/multi_server_provider.dart';
import 'providers/server_state_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/hidden_libraries_provider.dart';
import 'providers/playback_state_provider.dart';
import 'providers/download_provider.dart';
import 'providers/offline_mode_provider.dart';
import 'providers/offline_watch_provider.dart';
import 'watch_together/watch_together.dart';
import 'services/multi_server_manager.dart';
import 'services/offline_watch_sync_service.dart';
import 'services/data_aggregation_service.dart';
import 'services/in_app_review_service.dart';
import 'services/server_registry.dart';
import 'services/download_manager_service.dart';
import 'services/download_storage_service.dart';
import 'services/plex_api_cache.dart';
import 'database/app_database.dart';
import 'utils/app_logger.dart';
import 'utils/orientation_helper.dart';
import 'utils/language_codes.dart';
import 'i18n/strings.g.dart';
import 'focus/input_mode_tracker.dart';

void main() async {
  // 1. 确保 Flutter 引擎与原生平台绑定已初始化。
  // 在异步 main 函数中，如果需要在 runApp() 之前调用原生插件（如 SharedPreferences 或 window_manager），
  // 必须先调用此方法，否则平台通道（Platform Channels）将无法建立，导致原生调用失败。
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 初始化设置服务单例并加载本地存储的偏好设置。
  // 我们需要先获取 settings 实例，因为后续的应用初始化逻辑（如语言选择、日志级别、下载路径等）都强依赖于用户的个性化配置。
  final settings = await SettingsService.getInstance();

  // 3. 从本地存储中读取用户保存的语言设置。
  // 提前读取语言是为了在应用界面渲染前就确定好正确的语言上下文，防止应用启动后因异步加载语言包而导致的界面文字瞬时中英文跳变（闪烁）。
  final savedLocale = settings.getAppLocale();

  // 4. 将读取到的语言设置应用到国际化库（slang/i18n）。
  // 这样做可以确保全局静态变量 `t` 指向正确的语言资源。
  LocaleSettings.setLocale(savedLocale);

  // 5. 为大型媒体库优化图片缓存策略。
  // Plex 应用通常包含海量的海报和剧照，默认的缓存大小可能不足，导致滚动时频繁触发图片解码和垃圾回收。
  // 将缓存提升至 200MB 可以显著提高列表滚动的平滑度。
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20; // 200MB

  // 6. 准备并行初始化列表。
  // 启动耗时是影响用户体验的关键指标。对于不互相依赖的初始化任务（如桌面窗口管理、手柄检测等），
  // 采用并行初始化而非顺序等待可以最大化利用系统资源，缩短整体冷启动时间。
  final futures = <Future<void>>[];

  // 7. 针对桌面端平台初始化窗口管理器。
  // window_manager 插件用于控制原生窗口（如隐藏标题栏、设置最小尺寸、记忆窗口位置等），
  // 这些是桌面应用提供“原生感”体验的基础。
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    futures.add(windowManager.ensureInitialized());
  }

  // 8. 针对 Android 平台初始化 TV 检测服务。
  // Android TV 与手机版在交互逻辑上有本质区别（遥控器 vs 触摸）。
  // 提前识别设备类型，以便后续 UI 能够正确应用焦点管理逻辑和适配大屏布局。
  if (Platform.isAndroid) {
    futures.add(TvDetectionService.getInstance().then((_) {}));
  }

  // 9. 配置 macOS 的自定义标题栏样式。
  // 在 macOS 上，为了实现沉浸式的视觉效果，我们通常会隐藏标准标题栏并使用自定义组件，
  // 这需要调用原生 API 来调整交通灯按钮的位置和窗口背景。
  futures.add(MacOSTitlebarService.setupCustomTitlebar());

  // 10. 初始化通用的持久化存储服务。
  // StorageService 封装了基础的键值对存储，是其他高级服务（如 ServerRegistry）的基础。
  futures.add(StorageService.getInstance().then((_) {}));

  // 11. 初始化音轨/字幕所需的语言代码映射表。
  // 播放器获取到的流信息通常是 ISO 代码（如 'eng'），需要映射为用户可读的文字（如 'English'）。
  futures.add(LanguageCodes.initialize());

  // 12. 等待上述所有并行异步任务完成。
  // 确保在进入下一阶段逻辑前，所有基础底层服务都已就绪。
  await Future.wait(futures);

  // 13. 根据用户偏好配置日志系统。
  // 生产环境默认应限制日志输出以保护隐私并减少性能开销，但在排查问题时，用户可以开启调试模式。
  final debugEnabled = settings.getEnableDebugLogging();
  setLoggerLevel(debugEnabled);

  // 14. 初始化下载管理所需的存储路径。
  // 下载服务需要知道具体在哪个目录下创建文件。由于目录可能随设置改变，
  // 因此必须在 settings 就绪后才能执行此初始化。
  await DownloadStorageService.instance.initialize(settings);

  // 15. 启动全局全屏状态管理监控。
  // 视频播放器需要根据播放/暂停状态动态控制系统的状态栏隐藏、屏幕常亮以及窗口全屏切换。
  FullscreenStateManager().startMonitoring();

  // 16. 针对桌面端启动游戏手柄支持和 Discord 丰富状态（Rich Presence）同步。
  // 手柄支持提升了沙发场景下的操作体验；Discord 同步则为用户提供了社交展示功能。
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    GamepadService.instance.start();
    DiscordRPCService.instance.initialize();
  }

  // 17. 挂载并启动根 Flutter Widget。
  runApp(const MainApp());
}

// 全局 RouteObserver 用于跟踪页面导航。
// 这对于某些需要根据页面切换来暂停/恢复操作（如视频播放）的逻辑非常有用。
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  // 初始化多服务器架构相关的核心服务单例。
  // 这些服务负责管理服务器连接、数据聚合、本地数据库和下载任务。
  late final MultiServerManager _serverManager;
  late final DataAggregationService _aggregationService;
  late final AppDatabase _appDatabase;
  late final DownloadManagerService _downloadManager;
  late final OfflineWatchSyncService _offlineWatchSyncService;

  @override
  void initState() {
    super.initState();
    // 注册应用生命周期监听器。
    // 这允许我们在应用进入后台时暂停任务，或在恢复前台时触发同步。
    WidgetsBinding.instance.addObserver(this);

    _serverManager = MultiServerManager();
    _aggregationService = DataAggregationService(_serverManager);
    _appDatabase = AppDatabase();

    // 使用数据库实例初始化 API 缓存。
    // 缓存机制可以显著减少重复的网络请求，并在离线模式下提供基础数据访问。
    PlexApiCache.initialize(_appDatabase);

    _downloadManager = DownloadManagerService(database: _appDatabase, storageService: DownloadStorageService.instance);

    _offlineWatchSyncService = OfflineWatchSyncService(database: _appDatabase, serverManager: _serverManager);

    // 启动应用内评分/评论的会话跟踪。
    // 这有助于在用户使用一段时间后适时弹出评分请求。
    InAppReviewService.instance.startSession();
  }

  @override
  void dispose() {
    // 组件销毁时移除监听器，防止内存泄漏。
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 响应应用生命周期变化。
    switch (state) {
      case AppLifecycleState.resumed:
        // 应用回到前台：触发离线观看记录同步，并开始新的评分会话。
        _offlineWatchSyncService.onAppResumed();
        InAppReviewService.instance.startSession();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // 应用进入后台或关闭：结束当前的评分会话统计。
        InAppReviewService.instance.endSession();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // 过渡状态：不执行特定逻辑。
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 MultiProvider 在 widget 树顶部注入全局状态。
    // 这种模式允许任何子组件方便地访问和响应这些服务的状态变化。
    return MultiProvider(
      providers: [
        // 兼容旧代码的 Provider。
        ChangeNotifierProvider(create: (context) => PlexClientProvider()),
        // 核心的多服务器管理 Provider。
        ChangeNotifierProvider(create: (context) => MultiServerProvider(_serverManager, _aggregationService)),
        ChangeNotifierProvider(create: (context) => ServerStateProvider()),
        // 离线模式 Provider，依赖于 MultiServerProvider 的连接状态。
        ChangeNotifierProxyProvider<MultiServerProvider, OfflineModeProvider>(
          create: (_) {
            final provider = OfflineModeProvider(_serverManager);
            provider.initialize(); // 立即初始化，确保 statusStream 监听器准备就绪。
            return provider;
          },
          update: (_, multiServerProvider, previous) {
            final provider = previous ?? OfflineModeProvider(_serverManager);
            provider.initialize(); // 初始化方法是幂等的，多次调用是安全的。
            return provider;
          },
        ),
        // 下载管理 Provider。
        ChangeNotifierProvider(create: (context) => DownloadProvider(downloadManager: _downloadManager)),
        // 离线观看同步服务，需要与下载服务和离线模式联动。
        ChangeNotifierProvider<OfflineWatchSyncService>(
          create: (context) {
            final offlineModeProvider = context.read<OfflineModeProvider>();
            final downloadProvider = context.read<DownloadProvider>();

            // 当离线观看记录同步完成后，通知下载 Provider 刷新元数据缓存（如已观看状态）。
            _offlineWatchSyncService.onWatchStatesRefreshed = () {
              downloadProvider.refreshMetadataFromCache();
            };

            // 开始监控网络连接，以便在网络恢复时自动触发同步。
            _offlineWatchSyncService.startConnectivityMonitoring(offlineModeProvider);
            return _offlineWatchSyncService;
          },
        ),
        // 离线观看 Provider，汇聚了同步服务、下载状态和 API 缓存的信息。
        ChangeNotifierProxyProvider2<OfflineWatchSyncService, DownloadProvider, OfflineWatchProvider>(
          create: (context) => OfflineWatchProvider(
            syncService: _offlineWatchSyncService,
            downloadProvider: context.read<DownloadProvider>(),
            apiCache: PlexApiCache.instance,
          ),
          update: (_, syncService, downloadProvider, previous) {
            return previous ??
                OfflineWatchProvider(
                  syncService: syncService,
                  downloadProvider: downloadProvider,
                  apiCache: PlexApiCache.instance,
                );
          },
        ),
        // 其他独立的状态管理 Providers。
        ChangeNotifierProvider(create: (context) => UserProfileProvider()),
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => SettingsProvider(), lazy: true),
        ChangeNotifierProvider(create: (context) => HiddenLibrariesProvider(), lazy: true),
        ChangeNotifierProvider(create: (context) => PlaybackStateProvider()),
        ChangeNotifierProvider(create: (context) => WatchTogetherProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          // TranslationProvider 负责国际化上下文。
          // InputModeTracker 负责追踪用户输入方式（鼠标 vs 遥控器）。
          return TranslationProvider(
            child: InputModeTracker(
              child: MaterialApp(
                title: t.app.title,
                debugShowCheckedModeBanner: false,
                theme: themeProvider.lightTheme,
                darkTheme: themeProvider.darkTheme,
                themeMode: themeProvider.materialThemeMode,
                navigatorObservers: [routeObserver],
                home: const OrientationAwareSetup(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class OrientationAwareSetup extends StatefulWidget {
  const OrientationAwareSetup({super.key});

  @override
  State<OrientationAwareSetup> createState() => _OrientationAwareSetupState();
}

class _OrientationAwareSetupState extends State<OrientationAwareSetup> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当依赖发生变化时（如从播放器返回），恢复默认的屏幕旋转偏好。
    _setOrientationPreferences();
  }

  void _setOrientationPreferences() {
    // 确保非视频播放页面遵循系统的默认方向设置（通常是根据设置锁定或自动旋转）。
    OrientationHelper.restoreDefaultOrientations(context);
  }

  @override
  Widget build(BuildContext context) {
    return const SetupScreen();
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  @override
  void initState() {
    super.initState();
    // 启动时加载已保存的凭据并尝试连接服务器。
    _loadSavedCredentials();
  }

  Future<void> _checkForUpdatesOnStartup() async {
    // 稍微延迟检查更新，避免与启动时的密集 IO 竞争资源，确保 UI 渲染流畅。
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    try {
      final updateInfo = await UpdateService.checkForUpdatesOnStartup();

      if (updateInfo != null && updateInfo['hasUpdate'] == true && mounted) {
        _showUpdateDialog(updateInfo);
      }
    } catch (e) {
      appLogger.e('Error checking for updates', error: e);
    }
  }

  void _showUpdateDialog(Map<String, dynamic> updateInfo) {
    // 显示更新对话框，告知用户有新版本可用。
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(t.update.available),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.update.versionAvailable(version: updateInfo['latestVersion']),
                style: Theme.of(dialogContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                t.update.currentVersion(version: updateInfo['currentVersion']),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: Text(t.common.later),
            ),
            TextButton(
              onPressed: () async {
                // 用户选择跳过此版本，记录到本地存储。
                await UpdateService.skipVersion(updateInfo['latestVersion']);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(t.update.skipVersion),
            ),
            FilledButton(
              onPressed: () async {
                // 打开浏览器跳转到发布页面。
                final url = Uri.parse(updateInfo['releaseUrl']);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(t.update.viewRelease),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadSavedCredentials() async {
    final storage = await StorageService.getInstance();
    final registry = ServerRegistry(storage);

    // 1. 如果是旧版本升级，执行单服务器到多服务器配置的迁移。
    await registry.migrateFromSingleServer();

    // 2. 从 Plex 官方 API 刷新服务器列表。
    // 服务器的内网/外网 IP 可能会发生变化，必须定期刷新以保证连接有效性。
    await registry.refreshServersFromApi();

    // 3. 读取所有配置好的服务器信息。
    final servers = await registry.getServers();

    if (servers.isEmpty) {
      // 如果没有任何服务器配置，说明是新用户或已退出登录，跳转到认证页面。
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthScreen()));
      }
      return;
    }

    if (!mounted) return;
    final multiServerProvider = Provider.of<MultiServerProvider>(context, listen: false);

    try {
      appLogger.i('Connecting to ${servers.length} servers...');

      // 获取或生成客户端唯一标识，用于在 Plex 服务端识别本设备。
      final clientId = storage.getClientIdentifier();

      // 4. 并行尝试连接所有服务器。
      // 设置超时时间（10秒），防止个别不通的服务器拖慢整体启动流程。
      final connectedCount = await multiServerProvider.serverManager.connectToAllServers(
        servers,
        clientIdentifier: clientId,
        timeout: const Duration(seconds: 10),
        onServerConnected: (serverId, client) {
          // 兼容性逻辑：将第一个连接成功的客户端设为旧版 Provider 的默认客户端。
          final legacyProvider = Provider.of<PlexClientProvider>(context, listen: false);
          if (legacyProvider.client == null) {
            legacyProvider.setClient(client);
          }
        },
      );

      if (connectedCount > 0) {
        // 只要有一个服务器连接成功，应用就可以正常进入主界面。
        appLogger.i('Successfully connected to $connectedCount servers');

        if (mounted) {
          // 服务器就绪后，触发一次离线观看状态同步。
          context.read<OfflineWatchSyncService>().onServersConnected();

          // 跳转到主屏幕。
          final firstClient = multiServerProvider.serverManager.onlineClients.values.first;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => MainScreen(client: firstClient)));

          // 在后台检查应用更新，不阻塞主 UI。
          _checkForUpdatesOnStartup();
        }
      } else {
        // 如果所有服务器都无法连接，则自动进入离线模式。
        // 在此模式下，用户依然可以观看已下载的内容。
        appLogger.w('Failed to connect to any servers, entering offline mode');

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen(isOfflineMode: true)),
          );
        }
      }
    } catch (e, stackTrace) {
      appLogger.e('Error during multi-server connection', error: e, stackTrace: stackTrace);

      if (mounted) {
        // 发生严重错误时，作为兜底也进入离线模式。
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen(isOfflineMode: true)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(t.app.loading)],
        ),
      ),
    );
  }
}
