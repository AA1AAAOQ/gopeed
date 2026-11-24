import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

import '../../util.dart';
import '../../win32.dart';

doRegisterUrlScheme(String scheme) {
  if (Util.isWindows()) {
    final schemeKey = 'Software\\Classes\\$scheme';
    final appPath = Platform.resolvedExecutable;

    upsertRegistry(
      schemeKey,
      'URL Protocol',
      '',
    );
    upsertRegistry(
      '$schemeKey\\shell\\open\\command',
      '',
      '"$appPath" "%1"',
    );
  }
}

doUnregisterUrlScheme(String scheme) {
  if (Util.isWindows()) {
    Registry.currentUser
        .deleteKey('Software\\Classes\\$scheme', recursive: true);
  }
}

const _torrentRegKey = 'Software\\Classes\\.torrent';
const _torrentRegValue = 'Gopeed_torrent';
const _torrentAppRegKey = 'Software\\Classes\\$_torrentRegValue';

/// BT support is gone, drop the magnet scheme and the .torrent file type
/// registration an older version may have left behind.
doUnregisterDefaultTorrentClient() {
  if (Util.isWindows()) {
    doUnregisterUrlScheme("magnet");
    Registry.currentUser.deleteKey(_torrentRegKey, recursive: true);
    Registry.currentUser.deleteKey(_torrentAppRegKey, recursive: true);
  }
}