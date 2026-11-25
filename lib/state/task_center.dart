import 'package:flutter/widgets.dart';

import '../git/progress.dart';

enum AppTaskStatus { running, succeeded, failed, cancelled }

class AppTask {
  AppTask(this.id, this.title, this.subtitle) : startedAt = DateTime.now();

  final int id;
  final String title;
  final String? subtitle;
  final DateTime startedAt;
  DateTime? finishedAt;
  AppTaskStatus status = AppTaskStatus.running;
  GitProgress? progress;
  String? error;

  /// Invoked when the user asks to cancel the task; null when the operation
  /// cannot be interrupted.
  void Function()? onCancel;

  bool get running => status == AppTaskStatus.running;
  bool get cancellable => running && onCancel != null;
}

/// Background operations across every open repository, including clones that
/// do not have a repository controller yet.
class TaskCenter extends ChangeNotifier {
  final List<AppTask> tasks = [];
  var _nextId = 0;

  Iterable<AppTask> get active =>
      tasks.where((task) => task.status == AppTaskStatus.running);
  int get activeCount => active.length;
  AppTask? get current => active.firstOrNull ?? tasks.firstOrNull;

  AppTask start(String title, {String? subtitle}) {
    final task = AppTask(++_nextId, title, subtitle);
    tasks.insert(0, task);
    if (tasks.length > 50) {
      tasks.removeRange(50, tasks.length);
    }
    notifyListeners();
    return task;
  }

  void update(AppTask task, GitProgress progress) {
    if (!task.running || identical(task.progress, progress)) return;
    final previous = task.progress;
    if (previous?.phase == progress.phase &&
        previous?.percent == progress.percent &&
        previous?.completed == progress.completed &&
        previous?.total == progress.total &&
        previous?.bytes == progress.bytes &&
        previous?.bytesPerSecond == progress.bytesPerSecond) {
      return;
    }
    task.progress = progress;
    notifyListeners();
  }

  void succeed(AppTask task) => _finish(task, AppTaskStatus.succeeded);

  void fail(AppTask task, String error) {
    task.error = error;
    _finish(task, AppTaskStatus.failed);
  }

  /// Asks the operation to stop. The task leaves the running state when the
  /// operation reports back (see [cancelled]), not when this is called.
  void cancel(AppTask task) {
    if (!task.cancellable) return;
    task.onCancel!();
  }

  void cancelled(AppTask task) => _finish(task, AppTaskStatus.cancelled);

  void _finish(AppTask task, AppTaskStatus status) {
    if (!task.running) return;
    task.status = status;
    task.finishedAt = DateTime.now();
    notifyListeners();
  }

  void remove(AppTask task) {
    if (task.running) return;
    tasks.remove(task);
    notifyListeners();
  }

  void clearFinished() {
    tasks.removeWhere((task) => !task.running);
    notifyListeners();
  }
}
