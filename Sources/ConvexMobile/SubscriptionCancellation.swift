//
//  SubscriptionCancellation.swift
//  ConvexMobile
//

import Foundation
@preconcurrency @_exported import UniFFI

actor SubscriptionCancellation {
  private var task: Task<Void, Never>?
  private var handle: SubscriptionHandle?
  private var isCancelled = false

  func set(task: Task<Void, Never>) {
    if isCancelled {
      task.cancel()
      return
    }

    self.task = task
  }

  func set(handle: SubscriptionHandle) {
    if isCancelled {
      handle.cancel()
      return
    }

    self.handle = handle
  }

  func cancel() {
    isCancelled = true
    let task = task
    let handle = handle
    self.task = nil
    self.handle = nil

    task?.cancel()
    handle?.cancel()
  }
}
