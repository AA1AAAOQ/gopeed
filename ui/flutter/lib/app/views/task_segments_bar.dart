import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../api/model/task.dart';
import '../../api/model/task_stats.dart';
import '../services/task_stream_service.dart';

/// IDM / NDM style progress bar: the whole bar is the file, every connection
/// owns a slice of it (`begin`..`end`) and the slice is filled by its own
/// progress. Falls back to a plain progress bar when no stats are available
/// yet (task just created, paused/done task, non http protocol, ...).
class TaskSegmentsBar extends StatelessWidget {
  final Task task;

  /// Fallback progress 0..1 used when there are no connection stats.
  final double progress;
  final double height;

  const TaskSegmentsBar({
    Key? key,
    required this.task,
    required this.progress,
    this.height = 6,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final stream = Get.isRegistered<TaskStreamService>()
        ? Get.find<TaskStreamService>()
        : null;
    final colorScheme = Theme.of(context).colorScheme;
    return Obx(() {
      final stats = stream?.stats[task.id];
      final connections = stats?.connections ?? const <TaskConnectionStats>[];
      final total = (stats?.total ?? 0) > 0
          ? stats!.total
          : (task.meta.res?.size ?? 0);
      if (connections.isEmpty || total <= 0) {
        return LinearProgressIndicator(value: progress);
      }
      final completed = connections.where((c) => c.completed).length;
      final text = '${connections.length} 连接 · $completed 已完成';
      return Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 400),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SegmentsPainter(
              connections: connections,
              total: total,
              track: colorScheme.surfaceContainerHighest,
              primary: colorScheme.primary,
              completedColor: Colors.green,
              failedColor: colorScheme.error,
              connectingColor: Colors.amber,
              idleColor: colorScheme.outline,
            ),
          ),
        ),
      );
    });
  }
}

class _SegmentsPainter extends CustomPainter {
  final List<TaskConnectionStats> connections;
  final int total;
  final Color track;
  final Color primary;
  final Color completedColor;
  final Color failedColor;
  final Color connectingColor;
  final Color idleColor;

  _SegmentsPainter({
    required this.connections,
    required this.total,
    required this.track,
    required this.primary,
    required this.completedColor,
    required this.failedColor,
    required this.connectingColor,
    required this.idleColor,
  });

  Color _stateColor(TaskConnectionStats c) {
    if (c.failed) {
      return failedColor;
    }
    switch (c.state) {
      case 'completed':
        return completedColor;
      case 'downloading':
        return primary;
      case 'connecting':
        return connectingColor;
      default:
        return idleColor;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || total <= 0) {
      return;
    }
    final radius = Radius.circular(size.height / 2);
    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), Paint()..color = track);

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, radius));
    for (final c in connections) {
      final x0 = max(0.0, c.begin / total) * size.width;
      final x1 = min(1.0, (c.end + 1) / total) * size.width;
      final w = x1 - x0;
      if (w <= 0) {
        continue;
      }
      final color = _stateColor(c);
      // The slice background shows the whole range the connection owns, the
      // solid part is what it already downloaded.
      canvas.drawRect(Rect.fromLTWH(x0, 0, w, size.height),
          Paint()..color = color.withValues(alpha: 0.22));
      final filled = w * c.ratio;
      if (filled > 0) {
        canvas.drawRect(Rect.fromLTWH(x0, 0, filled, size.height),
            Paint()..color = color);
      }
      // 1px separator so neighbouring slices stay readable
      if (w > 2.5) {
        canvas.drawRect(Rect.fromLTWH(x1 - 0.7, 0, 0.7, size.height),
            Paint()..color = track);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SegmentsPainter old) {
    if (old.total != total || old.connections.length != connections.length) {
      return true;
    }
    for (var i = 0; i < connections.length; i++) {
      final a = old.connections[i];
      final b = connections[i];
      if (a.begin != b.begin ||
          a.end != b.end ||
          a.downloaded != b.downloaded ||
          a.state != b.state ||
          a.failed != b.failed) {
        return true;
      }
    }
    return old.track != track || old.primary != primary;
  }
}