
import 'dart:async';

enum ExecutionType {
  signalCollection,
  signalInvocation,
  signalClosure
}

class Task {
  final ExecutionType type;
  final int? invocationId;
  final Function()? close;
  Task(this.type, {this.close, this.invocationId});
}

TaskPoolExecutor? currentTaskPool() {
   final supposedContext = Zone.current[#flow.context];
   if (supposedContext is TaskPoolExecutor) {
     return supposedContext;
   }
   return null;
}

final class TaskPool {
  final int taskPoolId;

  final List<Task> shutdownHooks = [];

  TaskPool(this.taskPoolId);

  void attemptTaskCompleted(int invocationId) {
    _executeCallbacks(shutdownHooks, invocationId);
  }

  void addShutDownHook(Task action) {
    shutdownHooks.add(action);
  }

  /// Executes the registered callbacks based on the provided list of tasks.
  ///
  /// The method iterates through the list of tasks and determines the appropriate
  /// action to take based on the type of each task and the provided invocation ID.
  /// It clears the shutdown hooks if a task completion is marked.
  ///
  /// Example:
  ///
  /// [Task(collection), Task(invocation), Task(invocation), Task(invocation), Task(collection)]
  ///
  /// The last invocation after a collection signals the root that should be be triggered when
  /// ExecutionType.closure is sent
  void _executeCallbacks(List<Task> callbacks, [int? invocationId]) {
    int lastListenIndex = -1;
    bool cleared = false;
    for (int i = 0; i < callbacks.length; i++) {
      if (callbacks[i].type == ExecutionType.signalCollection && lastListenIndex != -1) {
        final invocable = callbacks[lastListenIndex];
        if (invocationId != null && invocationId == invocable.invocationId) {
          invocable.close?.call();
          cleared = true;
        }
        lastListenIndex = -1;
      } else if (callbacks[i].type == ExecutionType.signalInvocation) {
        lastListenIndex = i;
      }

      if (i == callbacks.length - 1 && callbacks[i].type == ExecutionType.signalInvocation) {
        final invocable = callbacks[i];
        if (invocationId != null && invocationId == invocable.invocationId) {
          invocable.close?.call();
          cleared = true;
        }
      }

      if (cleared) {
        shutdownHooks.clear();
      }
    }
  }
}

final class TaskPoolExecutor {
  final Map<int, TaskPool> _taskPools = {};

  void registerTask(Task action) {
    final taskPoolId = Zone.current.hashCode;
    final TaskPool taskPool = _taskPools.putIfAbsent(taskPoolId, () => TaskPool(taskPoolId));
    if (action.type == ExecutionType.signalClosure) {
      taskPool.attemptTaskCompleted(action.invocationId ?? -1);
      return;
    }
    taskPool.addShutDownHook(action);
  }

  ZoneSpecification get config => const ZoneSpecification();
}

