import Foundation

actor TaskCoordinator {
  private var tasks = Set<Task<Void, Never>>()

  @discardableResult
  func task(
    priority: TaskPriority? = nil,
    operation: @escaping @Sendable () async -> Void
  ) -> Task<Void, Never> {
    let task = Task(priority: priority) {
      await operation()
    }

    track(task)
    return task
  }

  func track(_ task: Task<Void, Never>) {
    tasks.insert(task)

    Task { [task] in
      await task.value
      remove(task)
    }
  }

  func cancelAll() {
    let activeTasks = tasks
    tasks.removeAll()

    for task in activeTasks {
      task.cancel()
    }
  }

  private func remove(_ task: Task<Void, Never>) {
    tasks.remove(task)
  }
}
