import 'dart:async';

import 'package:get/get.dart';

import '../../../../api/api.dart';
import '../../../../api/model/task.dart';
import '../../../services/task_stream_service.dart';

abstract class TaskListController extends GetxController {
  List<Status> statuses;
  int Function(Task a, Task b) compare;

  TaskListController(this.statuses, this.compare);

  final tasks = <Task>[].obs;
  final selectedTaskIds = <String>[].obs;
  final isRunning = false.obs;

  late final Timer _timer;

  TaskStreamService? get _stream => Get.isRegistered<TaskStreamService>()
      ? Get.find<TaskStreamService>()
      : null;

  @override
  void onInit() async {
    super.onInit();

    final stream = _stream;
    if (stream != null && stream.isSupported) {
      // The server sent events stream is the primary source, keep this list in
      // sync with it and fall back to polling when it gets disconnected.
      ever(stream.tasks, (_) => _applyStreamTasks());
      ever(stream.connected, (connected) {
        if (connected) {
          isRunning.value = true;
          _applyStreamTasks();
        } else {
          start();
        }
      });
      // Paint the current state right away, the stream takes over as soon as
      // the first frame arrives.
      await getTasksState();
      isRunning.value = true;
    } else {
      start();
    }

    _timer = Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
      if (!isRunning.value) {
        return;
      }
      final s = _stream;
      if (s != null && s.connected.value) {
        // Realtime stream is alive, no need to poll.
        return;
      }
      await getTasksState();
    });
  }

  @override
  void onClose() {
    super.onClose();
    _timer.cancel();
  }

  void start() async {
    await getTasksState();
    isRunning.value = true;
  }

  void stop() {
    isRunning.value = false;
  }

  void _applyStreamTasks() {
    final stream = _stream;
    if (stream == null || !stream.hasTasksFrame.value) {
      return;
    }
    if (!isRunning.value) {
      return;
    }
    final filtered = stream.tasks
        .where((task) => statuses.contains(task.status))
        .toList();
    filtered.sort(compare);
    tasks.value = filtered;
  }

  getTasksState() async {
    final tasks = await getTasks(statuses);
    // sort tasks by create time
    tasks.sort(compare);
    this.tasks.value = tasks;
  }
}