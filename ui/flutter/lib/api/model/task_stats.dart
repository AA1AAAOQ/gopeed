/// Per connection progress of a running task, mirrors `StatsConnection` of the
/// go core (`pkg/protocol/http/model.go`).
class TaskConnectionStats {
  /// Connection index, stable for the lifetime of the task.
  final int id;

  /// One of resolve / primary / worker.
  final String role;

  /// One of notStarted / connecting / downloading / completed / failed.
  final String state;

  /// Inclusive byte range the connection is responsible for.
  final int begin;
  final int end;

  /// Bytes already written inside [begin, end].
  final int downloaded;

  /// Recent speed of this connection in bytes per second.
  final int speed;

  final bool completed;
  final bool failed;
  final int retryTimes;

  TaskConnectionStats({
    required this.id,
    required this.role,
    required this.state,
    required this.begin,
    required this.end,
    required this.downloaded,
    required this.speed,
    required this.completed,
    required this.failed,
    required this.retryTimes,
  });

  factory TaskConnectionStats.fromJson(Map<String, dynamic> json) {
    return TaskConnectionStats(
      id: (json['id'] as num?)?.toInt() ?? 0,
      role: json['role'] as String? ?? 'worker',
      state: json['state'] as String? ?? 'notStarted',
      begin: (json['begin'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
      downloaded: (json['downloaded'] as num?)?.toInt() ?? 0,
      speed: (json['speed'] as num?)?.toInt() ?? 0,
      completed: json['completed'] as bool? ?? false,
      failed: json['failed'] as bool? ?? false,
      retryTimes: (json['retryTimes'] as num?)?.toInt() ?? 0,
    );
  }

  /// Size of the range this connection owns.
  int get size => end - begin + 1;

  /// How much of its own range is done, 0..1.
  double get ratio {
    if (size <= 0) {
      return 0;
    }
    final r = downloaded / size;
    if (r.isNaN) {
      return 0;
    }
    return r.clamp(0.0, 1.0);
  }
}

/// Overall stats of a task, mirrors `Stats` of the go core.
class TaskStats {
  /// Total size of the resource in bytes, 0 when unknown.
  final int total;
  final List<TaskConnectionStats> connections;

  TaskStats({required this.total, required this.connections});

  factory TaskStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return TaskStats(total: 0, connections: const []);
    }
    final rawConnections = (json['connections'] as List<dynamic>?) ?? const [];
    return TaskStats(
      total: (json['total'] as num?)?.toInt() ?? 0,
      connections: rawConnections
          .whereType<Map<String, dynamic>>()
          .map(TaskConnectionStats.fromJson)
          .toList(),
    );
  }
}