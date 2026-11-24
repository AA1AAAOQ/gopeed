import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../../api/api.dart';
import '../../api/model/task.dart';
import '../../api/model/task_stats.dart';
import '../../util/util.dart';

/// Keeps the task list and the per connection stats in sync with the go core by
/// consuming the server sent events stream (`GET /api/v1/tasks/stream`).
///
/// The stream is the near real time source of truth, the 1s polling in
/// `TaskListController` stays as a fallback for platforms where streaming is
/// not available (e.g. the web build).
class TaskStreamService extends GetxService {
  /// Full task list pushed by the core, only re-sent when it changed.
  final tasks = <Task>[].obs;

  /// Per connection stats of the running tasks, keyed by task id.
  final stats = <String, TaskStats>{}.obs;

  final connected = false.obs;

  /// Whether at least one task list frame has been received.
  final hasTasksFrame = false.obs;

  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  String _buffer = '';
  bool _stopped = false;

  bool get isSupported => !Util.isWeb();

  @override
  void onInit() {
    super.onInit();
    if (isSupported) {
      _connect();
    }
  }

  @override
  void onClose() {
    _stopped = true;
    _sub?.cancel();
    _reconnectTimer?.cancel();
    super.onClose();
  }

  Future<void> _connect() async {
    if (_stopped) {
      return;
    }
    try {
      final resp = await openTaskStream();
      final body = resp.data;
      if (body == null) {
        throw Exception('empty task stream');
      }
      _buffer = '';
      connected.value = true;
      _sub = body.stream.listen(
        _onData,
        onError: (e) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      connected.value = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    connected.value = false;
    _sub?.cancel();
    _sub = null;
    if (_stopped) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 1), _connect);
  }

  void _onData(dynamic chunk) {
    if (chunk is! List<int>) {
      return;
    }
    _buffer += utf8.decode(chunk, allowMalformed: true);
    while (true) {
      final idx = _buffer.indexOf('\n\n');
      if (idx < 0) {
        break;
      }
      final event = _buffer.substring(0, idx);
      _buffer = _buffer.substring(idx + 2);
      _handleEvent(event);
    }
  }

  void _handleEvent(String event) {
    for (final line in event.split('\n')) {
      if (!line.startsWith('data:')) {
        continue;
      }
      final data = line.substring(5).trim();
      if (data.isEmpty) {
        continue;
      }
      try {
        final json = jsonDecode(data);
        if (json is! Map<String, dynamic> || json['code'] != 0) {
          continue;
        }
        final payload = json['data'];
        if (payload is! Map<String, dynamic>) {
          continue;
        }
        final tasksJson = payload['tasks'];
        if (tasksJson is List) {
          tasks.value = tasksJson
              .whereType<Map<String, dynamic>>()
              .map(Task.fromJson)
              .toList();
          hasTasksFrame.value = true;
        }
        final statsJson = payload['stats'];
        if (statsJson is Map<String, dynamic>) {
          // Merge so a paused task keeps showing the slices of its last frame,
          // and drop the ids that left the task list.
          final next = Map<String, TaskStats>.from(stats.value);
          statsJson.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              next[key] = TaskStats.fromJson(value);
            }
          });
          if (tasks.isNotEmpty) {
            final ids = tasks.map((t) => t.id).toSet();
            next.removeWhere((key, value) => !ids.contains(key));
          }
          stats.value = next;
        }
      } catch (e) {
        // A malformed frame must not kill the stream.
      }
    }
  }
}