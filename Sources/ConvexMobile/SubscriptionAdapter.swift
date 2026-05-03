import Foundation
@preconcurrency import UniFFI

final class SubscriptionAdapter<T: Decodable & Sendable>: QuerySubscriber {
  typealias Continuation = AsyncThrowingStream<T, Error>.Continuation

  let continuation: Continuation

  init(continuation: Continuation) {
    self.continuation = continuation
  }

  func onError(message: String, value: String?) {
    let err: ClientError
    if let value {
      err = ClientError.ConvexError(data: value)
    } else {
      err = ClientError.ServerError(msg: message)
    }
    continuation.finish(throwing: err)
  }

  func onUpdate(value: String) {
    do {
      continuation.yield(try JSONDecoder().decode(T.self, from: Data(value.utf8)))
    } catch {
      continuation.finish(throwing: error)
    }
  }
}
