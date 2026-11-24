import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:get/get.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_handler/share_handler.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:uri_to_file/uri_to_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';


import '../../../../api/api.dart';
import '../../../../api/model/create_task.dart';
import '../../../../api/model/downloader_config.dart';
import '../../../../api/model/install_extension.dart';
import '../../../../api/model/request.dart';
import '../../../../api/model/result.dart';
import '../../../../core/common/start_config.dart';
import '../../../../core/libgopeed_boot.dart';
import '../../../../database/database.dart';
import '../../../../database/entity.dart';
import '../../../../i18n/message.dart';
import '../../../../main.dart';
import '../../../../util/github_mirror.dart';
import '../../../../util/locale_manager.dart';
import '../../../../util/log_util.dart';
import '../../../../util/package_info.dart';
import '../../../../util/updater.dart';
import '../../../../util/util.dart';
import '../../../routes/app_pages.dart';
import '../../../rpc/rpc.dart';
import '../../redirect/views/redirect_view.dart';
import '../../task/controllers/task_controller.dart';
import '../../../services/notification_service.dart';
import '../../../services/task_stream_service.dart';

const unixSocketPath = 'gopeed.sock';

/// Represents a task that is pending URL update via listen mode.
class PendingUpdateTask {
  final String id;
  final String name;

  PendingUpdateTask({required this.id, required this.name});
}

/// When the main window should be popped up for a download task.
class TaskPopupTiming {
  static const off = 'off';
  static const start = 'start';
  static const done = 'done';
  static const both = 'both';

  static const values = [off, start, done, both];

  /// Task page tabs: 0 = downloading, 1 = downloaded.
  static const tabOfStart = 0;
  static const tabOfDone = 1;

  static String labelKey(String timing) =>
      'popupTiming${timing[0].toUpperCase()}${timing.substring(1)}';
}

class AppController extends GetxController with WindowListener, TrayListener {
  static StartConfig? _defaultStartConfig;

  /// Command line --hidden flag passed from main.dart
  final bool hiddenFromArgs;

  AppController({this.hiddenFromArgs = false});

  final autoStartup = false.obs;
  final startConfig = StartConfig().obs;
  final runningPort = 0.obs;
  final downloaderConfig = DownloaderConfig().obs;

  /// The task that is pending URL update via listen mode.
  /// Stored here in AppController to persist across page navigations.
  final pendingUpdateTask = Rxn<PendingUpdateTask>();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void onReady() {
    super.onReady();

    _initDeepLinks().onError((error, stackTrace) =>
        logger.w("initDeepLinks error", error, stackTrace));

    _initWindows().onError((error, stackTrace) =>
        logger.w("initWindows error", error, stackTrace));
        
    if (Util.isDesktop()) {
      Get.put(NotificationService());
      // Near real time task list + per connection stats for the progress bars.
      Get.put(TaskStreamService());
    }

    _initTray().onError(
        (error, stackTrace) => logger.w("initTray error", error, stackTrace));

    _initRpcServer().onError((error, stackTrace) =>
        logger.w("initRpcServer error", error, stackTrace));

    _initForegroundTask().onError((error, stackTrace) =>
        logger.w("initForegroundTask error", error, stackTrace));

    _initLaunchAtStartup().onError((error, stackTrace) =>
        logger.w("initLaunchAtStartup error", error, stackTrace));

    _initCheckUpdate().onError((error, stackTrace) =>
        logger.w("initCheckUpdate error", error, stackTrace));
  }

  @override
  void onClose() {
    _linkSubscription?.cancel();
    trayManager.removeListener(this);
    LibgopeedBoot.instance.stop();
  }

  @override
  void onWindowClose() async {
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      windowManager.hide();
    }
  }

  // According to the system_manager document, make sure to call setState once on the onWindowFocus event.
  @override
  void onWindowFocus() {
    refresh();
    if (Util.isMacos() && Database.instance.getRunAsMenubarApp()) {
      windowManager.setSkipTaskbar(true);
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onWindowMaximize() {
    Database.instance.saveWindowState(WindowStateEntity(isMaximized: true));
  }

  @override
  void onWindowUnmaximize() {
    Database.instance.saveWindowState(WindowStateEntity(isMaximized: false));
  }

  final _windowsResizeSave = Util.debounce(() async {
    final size = await windowManager.getSize();
    Database.instance.saveWindowState(
        WindowStateEntity(width: size.width, height: size.height));
  }, 500);

  @override
  void onWindowResize() {
    _windowsResizeSave();
  }

  DateTime? _lastRevealTime;

  /// Restore the main window from tray/minimized state, bring it to the front
  /// and grab the focus. [tabIndex] switches the task page to the "downloading"
  /// (0) or "downloaded" (1) tab after the navigation.
  Future<void> revealMainWindow({String reason = '', int? tabIndex}) async {
    if (!Util.isDesktop()) {
      return;
    }
    try {
      if (Util.isMacos() && Database.instance.getRunAsMenubarApp()) {
        // Menubar mode hides the dock icon, show it again so the user can
        // find the window.
        await windowManager.setSkipTaskbar(false);
      }
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      // Put the window in the middle of the screen, it may be dragged off
      // screen before being hidden to the tray.
      await windowManager.center();
      await windowManager.focus();
      // Windows foreground lock may keep the window behind the current one.
      // Toggling always-on-top is the most reliable way to force it up.
      await Future.delayed(const Duration(milliseconds: 120));
      final focused = await windowManager.isFocused();
      if (!focused) {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setAlwaysOnTop(false);
      }
      await _focusTaskPage(tabIndex);
    } catch (e) {
      logger.w("reveal main window fail, reason: $reason", e, StackTrace.current);
    }
  }

  bool _isTaskPageVisible() {
    try {
      final conf = Get.rootDelegate.currentConfiguration;
      if (conf == null) {
        return false;
      }
      final path = conf.uri.path;
      return path == Routes.TASK || path.startsWith('${Routes.TASK}/');
    } catch (e) {
      return false;
    }
  }

  /// Make sure the task page is the current page, and switch its tab.
  Future<void> _focusTaskPage(int? tabIndex) async {
    try {
      if (!_isTaskPageVisible()) {
        Get.rootDelegate.offAndToNamed(Routes.TASK);
      }
      if (tabIndex == null) {
        return;
      }
      // The task binding runs with the navigation, give the page a moment to
      // register its controller before switching the tab.
      for (var i = 0; i < 10; i++) {
        if (Get.isRegistered<TaskController>()) {
          Get.find<TaskController>().switchTab(tabIndex);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      logger.w("switch to task page fail", e, StackTrace.current);
    }
  }

  /// Called when a new download task shows up (created by the create page,
  /// the browser extension, the REST API, a magnet link, the CLI, ...).
  void onTaskStarted({String? taskName}) {
    if (!Util.isDesktop() || !_popupOnStart) {
      return;
    }
    _revealForTask(taskName, tabIndex: TaskPopupTiming.tabOfStart);
  }

  /// Called when a task is done or failed.
  void onTaskFinished({String? taskName}) {
    if (!Util.isDesktop() || !_popupOnDone) {
      return;
    }
    _revealForTask(taskName, tabIndex: TaskPopupTiming.tabOfDone);
  }

  String get _popupTiming => Database.instance.getPopupOnTaskTiming();

  bool get _popupOnStart =>
      _popupTiming == TaskPopupTiming.start || _popupTiming == TaskPopupTiming.both;

  bool get _popupOnDone =>
      _popupTiming == TaskPopupTiming.done || _popupTiming == TaskPopupTiming.both;

  void _revealForTask(String? taskName, {int? tabIndex}) {
    final now = DateTime.now();
    // Debounce: a batch of tasks (torrent files, a bunch of links) must not
    // fight over the window for every single task.
    if (_lastRevealTime != null &&
        now.difference(_lastRevealTime!).inMilliseconds < 800) {
      return;
    }
    _lastRevealTime = now;
    logger.i("popup main window, task: ${taskName ?? ''}");
    revealMainWindow(reason: taskName ?? 'task event', tabIndex: tabIndex);
  }

  Future<void> _initDeepLinks() async {
    if (Util.isWeb()) {
      // For web, just show window
      return;
    }

    // Handle deep link
    _appLinks = AppLinks();

    // Handle link when app is in warm state (front or background)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
      await _handleDeepLink(uri);
    });

    // Get initial link for cold start - this works after runApp()
    Uri? initialLink;
    try {
      initialLink = await _appLinks.getInitialLink();
    } catch (e) {
      // ignore errors
    }

    // Determine if window should be hidden
    // Priority 1: gopeed: URL scheme hidden parameter
    // Priority 2: Command line --hidden flag
    bool shouldHide = hiddenFromArgs;
    if (initialLink?.scheme == "gopeed") {
      shouldHide = initialLink!.queryParameters["hidden"] == "true";
    }

    // Show window if not hidden (desktop only)
    if (Util.isDesktop() && !shouldHide) {
      await windowManager.show();
      await windowManager.focus();
    }

    // Handle initial link for deep link navigation
    if (initialLink != null) {
      _handleDeepLink(initialLink);
    }

    // Handle shared media, e.g. shared link from browser
    if (Util.isMobile()) {
      () async {
        final handler = ShareHandlerPlatform.instance;

        handler.sharedMediaStream.listen((SharedMedia media) {
          if (media.content?.isNotEmpty == true) {
            final uri = Uri.parse(media.content!);
            // content uri will be handled by the app_links plugin
            if (uri.scheme != "content") {
              _handleDeepLink(uri);
            }
          }
        });

        final media = await handler.getInitialSharedMedia();
        if (media?.content?.isNotEmpty == true) {
          _handleDeepLink(Uri.parse(media!.content!));
        }
      }();
    }
  }

  Future<void> _initWindows() async {
    if (!Util.isDesktop()) {
      return;
    }
    windowManager.addListener(this);
  }

  Future<void> _initTray() async {
    if (!Util.isDesktop()) {
      return;
    }
    if (Util.isWindows()) {
      await trayManager.setIcon('assets/tray_icon/icon.ico');
    } else if (Util.isMacos()) {
      await trayManager.setIcon('assets/tray_icon/icon_mac.png',
          isTemplate: true);
    } else if (Platform.environment.containsKey('FLATPAK_ID') ||
        Platform.environment.containsKey('SNAP')) {
      await trayManager.setIcon('com.gopeed.Gopeed');
    } else {
      await trayManager.setIcon('assets/tray_icon/icon.png');
    }
    final menu = Menu(items: [
      MenuItem(
        label: "show".tr,
        onClick: (menuItem) async => {
          await windowManager.show(),
        },
      ),
      MenuItem.separator(),
      MenuItem(
        label: "create".tr,
        onClick: (menuItem) async => {
          await windowManager.show(),
          await Get.rootDelegate.offAndToNamed(Routes.CREATE),
        },
      ),
      MenuItem(
        label: "startAll".tr,
        onClick: (menuItem) async => {continueAllTasks(null)},
      ),
      MenuItem(
        label: "pauseAll".tr,
        onClick: (menuItem) async => {pauseAllTasks(null)},
      ),
      MenuItem(
        label: 'setting'.tr,
        onClick: (menuItem) async => {
          await windowManager.show(),
          await Get.rootDelegate.offAndToNamed(Routes.SETTING),
        },
      ),
      MenuItem.separator(),
      MenuItem(
        label: 'donate'.tr,
        onClick: (menuItem) => {
          launchUrl(Uri.parse("https://gopeed.com/docs/donate"),
              mode: LaunchMode.externalApplication)
        },
      ),
      MenuItem(
        label: '${"version".tr}（${packageInfo.version}）',
      ),
      MenuItem.separator(),
      MenuItem(
        label: 'exit'.tr,
        onClick: (menuItem) async {
          try {
            await LibgopeedBoot.instance.stop();
          } catch (e) {
            logger.w("libgopeed stop fail", e);
          }
          windowManager.destroy();
        },
      ),
    ]);
    if (!Util.isLinux()) {
      // Linux seems not support setToolTip, refer to: https://github.com/GopeedLab/gopeed/issues/241
      await trayManager.setToolTip('Gopeed');
    }
    await trayManager.setContextMenu(menu);
    trayManager.addListener(this);
  }

  Future<void> _initRpcServer() async {
    if (!Util.isDesktop()) {
      return;
    }
    try {
      await startRpcServer({
        "/create": (ctx) async {
          final meta =
              ctx.request.headers["X-Gopeed-Host-Meta"]?.firstOrNull ?? "{}";
          final jsonMeta = jsonDecode(meta);
          final silent = jsonMeta['silent'] as bool? ?? false;
          final params = await ctx.readText();
          final createTaskParams = CreateTask.fromJson(_decodeParams(params));
          if (!silent || pendingUpdateTask.value != null) {
            await windowManager.show();
            _handleToCreate0(createTaskParams);
          } else {
            try {
              await createTask(createTaskParams);
            } catch (e) {
              logger.w(
                  "create task from extension fail", e, StackTrace.current);
            }
          }
        },
        "/forward": (ctx) async {
          try {
            final body = await ctx.readJSON();
            final method = (body['method'] as String?)?.toUpperCase() ?? 'GET';
            final path = (body['path'] as String?) ?? "/";
            final data = body['data'];
            final query = body['query'] as Map<String, dynamic>?;

            // Forward request to gopeed REST API
            final response = await forward(
              path,
              method: method,
              data: data,
              queryParameters: query,
            );

            // Return raw response
            await ctx.writeJSON(response.data);
          } catch (e) {
            if (e is DioException && e.response != null) {
              // Return API error response
              await ctx.writeJSON(e.response!.data);
            } else {
              await ctx.writeJSON(Result(code: 1, msg: e.toString()).toJson());
            }
          }
        },
      });
    } catch (e) {
      logger.w("start rpc server fail", e, StackTrace.current);
    }
  }

  Future<void> _initForegroundTask() async {
    if (!Util.isMobile()) {
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gopeed_service',
        channelName: 'Gopeed Background Service',
        channelImportance: NotificationChannelImportance.LOW,
        showWhen: true,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.restartService();
    } else {
      FlutterForegroundTask.startService(
        notificationTitle: "serviceTitle".tr,
        notificationText: "serviceText".tr,
        notificationIcon: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      );
    }
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme == "gopeed") {
      // gopeed:///create?params=eyJyZXEiOnsidXJsIjoiaHR0cHM6Ly9leGFtcGxlLmNvbS9maWxlLnR4dCJ9fQ==
      if (uri.path == "/create") {
        final params = uri.queryParameters["params"];
        if (params?.isNotEmpty == true) {
          _handleToCreate(params!);
          return;
        }
        Get.rootDelegate.offAndToNamed(Routes.CREATE);
        return;
      }
      // gopeed:///extension?params=eyJ1cmwiOiJodHRwczovL2dpdGh1Yi5jb20vbW9ua2V5V2llL2dvcGVlZC1leHRlbnNpb24tYmlsaWJpbGkiLCJkZXZNb2RlIjpmYWxzZX0=
      if (uri.path == "/extension") {
        final params = uri.queryParameters["params"];
        if (params?.isNotEmpty == true) {
          _handleToExtension(params!);
          return;
        }
        Get.rootDelegate.offAndToNamed(Routes.EXTENSION);
        return;
      }
      Get.rootDelegate.offAndToNamed(Routes.HOME);
      return;
    }

    String path;
    if (uri.scheme == "http" || uri.scheme == "https") {
      path = uri.toString();
    } else if (uri.scheme == "file") {
      path =
          Util.isWindows() ? Uri.decodeFull(uri.path.substring(1)) : uri.path;
    } else {
      path = (await toFile(uri.toString())).path;
    }
    Get.rootDelegate.offAndToNamed(Routes.REDIRECT,
        arguments: RedirectArgs(Routes.CREATE,
            arguments: CreateTask(req: Request(url: path))));
  }

  String runningAddress() {
    if (startConfig.value.network == 'unix') {
      return startConfig.value.address;
    }
    return '${startConfig.value.address.split(':').first}:$runningPort';
  }

  Future<StartConfig> _initDefaultStartConfig() async {
    if (_defaultStartConfig != null) {
      return _defaultStartConfig!;
    }
    _defaultStartConfig = StartConfig();
    if (!Util.supportUnixSocket()) {
      // not support unix socket, use tcp
      _defaultStartConfig!.network = "tcp";
      _defaultStartConfig!.address = "127.0.0.1:0";
    } else {
      _defaultStartConfig!.network = "unix";
      _defaultStartConfig!.address =
          "${(await getTemporaryDirectory()).path}/$unixSocketPath";
    }
    _defaultStartConfig!.apiToken = '';
    return _defaultStartConfig!;
  }

  Future<StartConfig> loadStartConfig() async {
    final defaultCfg = await _initDefaultStartConfig();
    final saveCfg = Database.instance.getStartConfig();
    startConfig.value.network = saveCfg?.network ?? defaultCfg.network;
    startConfig.value.address = saveCfg?.address ?? defaultCfg.address;
    startConfig.value.apiToken = saveCfg?.apiToken ?? defaultCfg.apiToken;
    return startConfig.value;
  }

  Future<DownloaderConfig> loadDownloaderConfig() async {
    try {
      downloaderConfig.value = await getConfig();
    } catch (e) {
      logger.w("load downloader config fail", e, StackTrace.current);
      downloaderConfig.value = DownloaderConfig();
    }
    await _initDownloaderConfig();
    return downloaderConfig.value;
  }

  _initDownloaderConfig() async {
    final config = downloaderConfig.value;
    final extra = config.extra;
    if (extra.themeMode.isEmpty) {
      extra.themeMode = ThemeMode.dark.name;
    }
    if (extra.locale.isEmpty) {
      final systemLocale = getLocaleKey(PlatformDispatcher.instance.locale);
      extra.locale = messages.keys.containsKey(systemLocale)
          ? systemLocale
          : getLocaleKey(fallbackLocale);
    }
    final proxy = config.proxy;
    if (proxy.scheme.isEmpty) {
      proxy.scheme = 'http';
    }

    if (config.downloadDir.isEmpty) {
      if (Util.isDesktop()) {
        config.downloadDir = (await getDownloadsDirectory())?.path ?? "./";
      } else if (Util.isAndroid()) {
        config.downloadDir = (await getExternalStorageDirectory())?.path ??
            (await getApplicationDocumentsDirectory()).path;
      } else if (Util.isIOS()) {
        config.downloadDir = (await getApplicationDocumentsDirectory()).path;
      } else {
        config.downloadDir = './';
      }
    }

    // Initialize default download categories if empty
    if (extra.downloadCategories.isEmpty) {
      _initDefaultDownloadCategories();
    }

    // Initialize default GitHub mirrors if empty
    if (extra.githubMirror.mirrors.isEmpty) {
      _initDefaultGithubMirrors();
    }
  }

  void _initDefaultDownloadCategories() {
    final extra = downloaderConfig.value.extra;
    final downloadDir = downloaderConfig.value.downloadDir;

    // Add default built-in categories with i18n keys
    // No need to set initial name value, it will be retrieved via nameKey
    extra.downloadCategories = [
      DownloadCategory(
        name: '',
        path: path.join(downloadDir, 'Music'),
        isBuiltIn: true,
        nameKey: 'categoryMusic',
      ),
      DownloadCategory(
        name: '',
        path: path.join(downloadDir, 'Video'),
        isBuiltIn: true,
        nameKey: 'categoryVideo',
      ),
      DownloadCategory(
        name: '',
        path: path.join(downloadDir, 'Document'),
        isBuiltIn: true,
        nameKey: 'categoryDocument',
      ),
      DownloadCategory(
        name: '',
        path: path.join(downloadDir, 'Program'),
        isBuiltIn: true,
        nameKey: 'categoryProgram',
      ),
    ];
  }

  void _initDefaultGithubMirrors() {
    final extra = downloaderConfig.value.extra;

    // Add default built-in GitHub mirrors
    extra.githubMirror.mirrors = [
      GithubMirror(
        type: GithubMirrorType.jsdelivr,
        url: 'https://fastly.jsdelivr.net/gh',
        isBuiltIn: true,
      ),
      GithubMirror(
        type: GithubMirrorType.ghProxy,
        url: 'https://fastgit.cc',
        isBuiltIn: true,
      ),
    ];
  }

  Future<void> _initLaunchAtStartup() async {
    if (!Util.isWindows() && !Util.isLinux()) {
      return;
    }
    launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
        args: ['--${StartupArgs.flagHidden}']);
    autoStartup.value = await launchAtStartup.isEnabled();
  }

  Future<void> _initCheckUpdate() async {
    // Check if auto check update is enabled
    if (!downloaderConfig.value.extra.notifyWhenNewVersion) {
      return;
    }

    final versionInfo = await checkUpdate();
    if (versionInfo != null) {
      await showUpdateDialog(Get.context!, versionInfo);
    }
  }

  Future<void> saveConfig() async {
    Database.instance.saveStartConfig(StartConfigEntity(
        network: startConfig.value.network,
        address: startConfig.value.address,
        apiToken: startConfig.value.apiToken));
    await putConfig(downloaderConfig.value);
  }

  Map<String, dynamic> _decodeParams(String params) {
    final safeParams = params.replaceAll('"', "").replaceAll(" ", "+");
    final paramsJson =
        String.fromCharCodes(base64Decode(base64.normalize(safeParams)));
    return jsonDecode(paramsJson);
  }

  _handleToCreate(String params) {
    final createTaskParams = CreateTask.fromJson(_decodeParams(params));
    _handleToCreate0(createTaskParams);
  }

  _handleToCreate0(CreateTask createTaskParams) {
    Get.rootDelegate.offAndToNamed(Routes.REDIRECT,
        arguments: RedirectArgs(Routes.CREATE, arguments: createTaskParams));
  }

  _handleToExtension(String params) {
    final installExtension = InstallExtension.fromJson(_decodeParams(params));
    Get.rootDelegate.offAndToNamed(Routes.REDIRECT,
        arguments: RedirectArgs(Routes.EXTENSION, arguments: installExtension));
  }
}
