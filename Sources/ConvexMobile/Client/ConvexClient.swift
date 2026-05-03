import Foundation
@preconcurrency import UniFFI

typealias RemoteCall = (String, [String: String]) async throws -> String

/// A client API for interacting with a Convex backend.
///
/// Handles marshalling of data between calling code and the
/// [convex-mobile](https://github.com/get-convex/convex-mobile) and
/// [convex-rs](https://github.com/get-convex/convex-rs) native libraries.
///
/// Consumers of this client should use Swift's ``Decodable``  protocol for handling data received from the
/// Convex backend.
public final class ConvexClient: @unchecked Sendable {
  let ffiClient: UniFFI.MobileConvexClientProtocol
  private let webSocketStateAdapter = WebSocketStateAdapter()

  /// Creates a new instance of ``ConvexClient``.
  ///
  /// - Parameters:
  ///   - deploymentUrl: The Convex backend URL to connect to; find it in the [dashboard](https://dashboard.convex.dev) Settings for your project
  public init(deploymentUrl: String) {
    self.ffiClient = UniFFI.MobileConvexClient(
      deploymentUrl: deploymentUrl, clientId: "swift-\(convexMobileVersion)", webSocketStateSubscriber: webSocketStateAdapter)
  }

  init(ffiClient: UniFFI.MobileConvexClientProtocol) {
    self.ffiClient = ffiClient
  }

  /// Subscribes to the query with the given `name` and streams decoded subscription updates.
  ///
  /// The upstream Convex subscription is canceled when the returned stream terminates.
  ///
  /// - Parameters:
  ///   - name: A value in "module:query_name"  format that will be used when calling the backend
  ///   - args: An optional ``Dictionary`` of arguments to be sent to the backend query function
  ///   - output: The type of data that will be returned in the stream, as a convenience to callers
  ///             where the type can't be easily inferred.
  public func stream<T: Decodable & Sendable>(
    to name: String, with args: [String: ConvexValue?]? = nil, yielding output: T.Type? = nil
  ) -> AsyncThrowingStream<T, Error> {
    let (stream, continuation) = AsyncThrowingStream<T, Error>.makeStream()
    let adapter = SubscriptionAdapter<T>(continuation: continuation)
    let cancellation = SubscriptionCancellation()

    continuation.onTermination = { _ in
      Task {
        await cancellation.cancel()
      }
    }

    let subscriptionTask = Task {
      do {
        let subscriptionHandle = try await self.ffiClient.subscribe(
          name: name,
          args: try ConvexArgumentEncoder.encode(args), subscriber: adapter)

        await cancellation.set(handle: subscriptionHandle)
      } catch is CancellationError {
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }

    Task {
      await cancellation.set(task: subscriptionTask)
    }

    return stream
  }

  /// Executes the query with the given `name` and `args` and returns the result.
  ///
  /// For queries that don't return a value, ignore the returned result.
  ///
  /// - Parameters:
  ///   - name: A value in "module:query_name"  format that will be used when calling the backend
  ///   - args: An optional ``Dictionary`` of arguments to be sent to the backend query function
  @discardableResult
  public func query<T: Decodable>(_ name: String, with args: [String: ConvexValue?]? = nil)
    async throws -> T
  {
    try await callForResult(name: name, args: args, remoteCall: ffiClient.query)
  }

  /// Executes the mutation with the given `name` and `args` and returns the result.
  ///
  /// For mutations that don't return a value, ignore the returned result.
  ///
  /// - Parameters:
  ///   - name: A value in "module:mutation_name"  format that will be used when calling the backend
  ///   - args: An optional ``Dictionary`` of arguments to be sent to the backend mutation function
  @discardableResult
  public func mutation<T: Decodable>(_ name: String, with args: [String: ConvexValue?]? = nil)
    async throws -> T
  {
    try await callForResult(name: name, args: args, remoteCall: ffiClient.mutation)
  }

  /// Executes the action with the given `name` and `args` and returns the result.
  ///
  /// For actions that don't return a value, ignore the returned result.
  ///
  /// - Parameters:
  ///   - name: A value in "module:mutation_name"  format that will be used when calling the backend
  ///   - args: An optional ``Dictionary`` of arguments to be sent to the backend mutation function
  @discardableResult
  public func action<T: Decodable>(_ name: String, with args: [String: ConvexValue?]? = nil)
    async throws -> T
  {
    return try await callForResult(name: name, args: args, remoteCall: ffiClient.action)
  }

  /// Common handler for `action` and `mutation` calls.
  ///
  /// To the client code, both work in a very similar fashion where remote code is invoked and a result is returned. This handler takes care of
  /// encoding the arguments and decoding the result, whether the call is an `action` or `mutation`.
  func callForResult<T: Decodable>(
    name: String, args: [String: ConvexValue?]? = nil, remoteCall: RemoteCall
  )
    async throws -> T
  {
    let rawResult = try await remoteCall(name, ConvexArgumentEncoder.encode(args))
    return try ConvexDecoder().decode(T.self, from: rawResult)
  }

  public func watchWebSocketStates() -> AsyncStream<ConvexWebSocketState> {
    return webSocketStateAdapter.stream()
  }

  func setAuthCallback(_ provider: (any AuthTokenProvider)?) async throws {
    try await ffiClient.setAuthCallback(provider: provider)
  }

}
