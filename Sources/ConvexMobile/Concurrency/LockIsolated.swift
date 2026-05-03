import Foundation

final class LockIsolated<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) {
    self.value = value
  }

  func withValue<Result>(_ operation: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer {
      lock.unlock()
    }
    return try operation(&value)
  }
}
