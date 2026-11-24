import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:gopeed/api/model/task.dart';

import 'task_downloaded_controller.dart';
import 'task_downloading_controller.dart';

class TaskController extends GetxController with GetSingleTickerProviderStateMixin {
  final tabIndex = 0.obs;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final selectTask = Rx<Task?>(null);

  late final TabController tabController =
      TabController(length: 2, vsync: this, initialIndex: tabIndex.value);

  @override
  void onInit() {
    super.onInit();
    if (kIsWeb) {
      BrowserContextMenu.disableContextMenu();
    }
  }

  @override
  void onClose() {
    tabController.dispose();
    super.onClose();
    if (kIsWeb) {
      BrowserContextMenu.enableContextMenu();
    }
  }

  /// Switch the task page to the downloading (0) or downloaded (1) tab.
  /// Used when the main window is popped up for a task event.
  void switchTab(int index) {
    if (index < 0 || index > 1) {
      return;
    }
    tabIndex.value = index;
    _syncPolling(index);
    if (tabController.index != index) {
      tabController.animateTo(index);
    }
  }

  void _syncPolling(int index) {
    if (index == 0) {
      if (Get.isRegistered<TaskDownloadingController>()) {
        Get.find<TaskDownloadingController>().start();
      }
      if (Get.isRegistered<TaskDownloadedController>()) {
        Get.find<TaskDownloadedController>().stop();
      }
    } else {
      if (Get.isRegistered<TaskDownloadingController>()) {
        Get.find<TaskDownloadingController>().stop();
      }
      if (Get.isRegistered<TaskDownloadedController>()) {
        Get.find<TaskDownloadedController>().start();
      }
    }
  }
}