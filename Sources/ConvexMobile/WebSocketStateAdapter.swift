import Foundation
@preconcurrency import UniFFI

final class WebSocketStateAdapter: WebSocketStateSubscriber {
  private let eventEmitter = EventEmitter<ConvexWebSocketState>()

  init() {}

  func onStateChange(state: UniFFI.WebSocketState) {
    eventEmitter.send(ConvexWebSocketState(state))
  }

  func stream() -> AsyncStream<ConvexWebSocketState> {
    return eventEmitter.events
  }
}
