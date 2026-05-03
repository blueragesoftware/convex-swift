import Foundation
@preconcurrency @_exported import UniFFI

public enum ConvexWebSocketState: Sendable, Equatable {
  case connected
  case connecting

  init(_ state: UniFFI.WebSocketState) {
    switch state {
    case .connected:
      self = .connected
    case .connecting:
      self = .connecting
    }
  }
}
