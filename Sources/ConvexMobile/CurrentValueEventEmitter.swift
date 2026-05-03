//
//  CurrentValueEventEmitter.swift
//  ConvexMobile
//

import Foundation

final class CurrentValueEventEmitter<Event: Sendable>: Sendable {
  private let state: LockIsolated<State>

  init(_ event: Event) {
    self.state = LockIsolated(State(currentEvent: event))
  }

  var events: AsyncStream<Event> {
    let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    let event = add(continuation, id: id)
    continuation.yield(event)

    continuation.onTermination = { [weak self] _ in
      self?.remove(id)
    }

    return stream
  }

  func send(_ event: Event) {
    let activeContinuations = state.withValue { state in
      state.currentEvent = event
      return Array(state.continuations.values)
    }

    for continuation in activeContinuations {
      continuation.yield(event)
    }
  }

  func finish() {
    let activeContinuations = state.withValue { state in
      let continuations = Array(state.continuations.values)
      state.continuations.removeAll()
      return continuations
    }

    for continuation in activeContinuations {
      continuation.finish()
    }
  }

  private func add(_ continuation: AsyncStream<Event>.Continuation, id: UUID) -> Event {
    state.withValue { state in
      state.continuations[id] = continuation
      return state.currentEvent
    }
  }

  private func remove(_ id: UUID) {
    state.withValue { state in
      state.continuations[id] = nil
    }
  }

  private struct State {
    var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    var currentEvent: Event
  }
}
