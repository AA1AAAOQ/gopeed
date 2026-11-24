import 'package:json_annotation/json_annotation.dart';

part 'downloader_config.g.dart';

@JsonSerializable(explicitToJson: true)
class DownloaderConfig {
  String downloadDir;
  int maxRunning;
  ProtocolConfig protocolConfig = ProtocolConfig();
  ExtraConfig extra = ExtraConfig();
  ProxyConfig proxy = ProxyConfig();
  WebhookConfig webhook = WebhookConfig();
  ScriptConfig script = ScriptConfig();
  AutoTorrentConfig autoTorrent = AutoTorrentConfig();
  ArchiveConfig archive = ArchiveConfig();
  bool autoDeleteMissingFileTasks;

  DownloaderConfig({
    this.downloadDir = '',
    this.maxRunning = 0,
    this.autoDeleteMissingFileTasks = false,
  });

  factory DownloaderConfig.fromJson(Map<String, dynamic> json) =>
      _$DownloaderConfigFromJson(json);

  Map<String, dynamic> toJson() => _$DownloaderConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class ProtocolConfig {
  HttpConfig http = HttpConfig();

  ProtocolConfig();

  factory ProtocolConfig.fromJson(Map<String, dynamic>? json) {
    final config = ProtocolConfig();
    final httpJson = json?['http'];
    if (httpJson is Map<String, dynamic>) {
      config.http = HttpConfig.fromJson(httpJson);
    }
    return config;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'http': http.toJson()};
}

@JsonSerializable()
class HttpConfig {
  String userAgent;
  int connections;
  bool useServerCtime;

  HttpConfig({
    this.userAgent = '',
    this.connections = 0,
    this.useServerCtime = false,
  });

  factory HttpConfig.fromJson(Map<String, dynamic> json) =>
      _$HttpConfigFromJson(json);

  Map<String, dynamic> toJson() => _$HttpConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class ExtraConfig {
  String themeMode;
  String locale;
  bool lastDeleteTaskKeep;
  bool defaultDirectDownload;
  bool notifyWhenNewVersion;
  bool autoStartTasks;
  bool desktopNotification;
  List<DownloadCategory> downloadCategories;

  ExtraConfigGithubMirror githubMirror = ExtraConfigGithubMirror();

  ExtraConfig({
    this.themeMode = '',
    this.locale = '',
    this.lastDeleteTaskKeep = false,
    this.defaultDirectDownload = false,
    this.notifyWhenNewVersion = true,
    this.autoStartTasks = false,
    this.desktopNotification = true,
    this.downloadCategories = const [],
  });

  factory ExtraConfig.fromJson(Map<String, dynamic>? json) =>
      json == null ? ExtraConfig() : _$ExtraConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ExtraConfigToJson(this);
}

@JsonSerializable()
class DownloadCategory {
  String name;
  String path;
  bool isBuiltIn;
  String? nameKey; // i18n key for built-in categories (e.g., 'categoryMusic')
  bool
      isDeleted; // Mark built-in categories as deleted instead of removing them

  DownloadCategory({
    required this.name,
    required this.path,
    this.isBuiltIn = false,
    this.nameKey,
    this.isDeleted = false,
  });

  factory DownloadCategory.fromJson(Map<String, dynamic> json) =>
      _$DownloadCategoryFromJson(json);

  Map<String, dynamic> toJson() => _$DownloadCategoryToJson(this);
}

@JsonSerializable()
class WebhookConfig {
  bool enable;
  List<String> urls;

  WebhookConfig({
    this.enable = false,
    this.urls = const [],
  });

  factory WebhookConfig.fromJson(Map<String, dynamic>? json) =>
      json == null ? WebhookConfig() : _$WebhookConfigFromJson(json);

  Map<String, dynamic> toJson() => _$WebhookConfigToJson(this);
}

@JsonSerializable()
class ScriptConfig {
  bool enable;
  List<String> paths;

  ScriptConfig({
    this.enable = false,
    this.paths = const [],
  });

  factory ScriptConfig.fromJson(Map<String, dynamic>? json) =>
      json == null ? ScriptConfig() : _$ScriptConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ScriptConfigToJson(this);
}

@JsonSerializable()
class ProxyConfig {
  bool enable;
  bool system;
  String scheme;
  String host;
  String usr;
  String pwd;

  ProxyConfig({
    this.enable = false,
    this.system = false,
    this.scheme = '',
    this.host = '',
    this.usr = '',
    this.pwd = '',
  });

  factory ProxyConfig.fromJson(Map<String, dynamic> json) =>
      _$ProxyConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ProxyConfigToJson(this);
}

enum GithubMirrorType {
  jsdelivr,
  ghProxy,
}

@JsonSerializable()
class GithubMirror {
  GithubMirrorType type;
  String url;
  bool isBuiltIn;
  bool isDeleted;

  GithubMirror({
    required this.type,
    required this.url,
    this.isBuiltIn = false,
    this.isDeleted = false,
  });

  factory GithubMirror.fromJson(Map<String, dynamic> json) =>
      _$GithubMirrorFromJson(json);

  Map<String, dynamic> toJson() => _$GithubMirrorToJson(this);
}

@JsonSerializable(explicitToJson: true)
class ExtraConfigGithubMirror {
  bool enabled;
  List<GithubMirror> mirrors;

  ExtraConfigGithubMirror({
    this.enabled = true,
    this.mirrors = const [],
  });

  factory ExtraConfigGithubMirror.fromJson(Map<String, dynamic>? json) =>
      json == null
          ? ExtraConfigGithubMirror()
          : _$ExtraConfigGithubMirrorFromJson(json);

  Map<String, dynamic> toJson() => _$ExtraConfigGithubMirrorToJson(this);
}

@JsonSerializable()
class AutoTorrentConfig {
  bool enable;
  bool deleteAfterDownload;

  AutoTorrentConfig({
    this.enable = false,
    this.deleteAfterDownload = false,
  });

  factory AutoTorrentConfig.fromJson(Map<String, dynamic>? json) =>
      json == null ? AutoTorrentConfig() : _$AutoTorrentConfigFromJson(json);

  Map<String, dynamic> toJson() => _$AutoTorrentConfigToJson(this);
}

@JsonSerializable()
class ArchiveConfig {
  bool autoExtract;
  bool deleteAfterExtract;

  ArchiveConfig({
    this.autoExtract = true,
    this.deleteAfterExtract = true,
  });

  factory ArchiveConfig.fromJson(Map<String, dynamic>? json) =>
      json == null ? ArchiveConfig() : _$ArchiveConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ArchiveConfigToJson(this);
}
