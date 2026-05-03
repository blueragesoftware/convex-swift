import Foundation
@preconcurrency import UniFFI

/// A Convex client that coordinates authentication through an ``AuthProvider``.
///
/// This type composes a ``ConvexClient`` instead of subclassing it. The transport client stays responsible for
/// queries, mutations, actions, and subscriptions; this wrapper owns auth state, token refresh, and the UniFFI
/// auth callback bridge.
public final class ConvexClientWithAuth<T: Sendable>: Sendable {
  private let client: ConvexClient
  private let authStateEmitter = CurrentValueEventEmitter<AuthState<T>>(.unauthenticated)
  private let authBridgeStore = AuthBridgeStore()
  private let taskCoordinator = TaskCoordinator()
  private let authProvider: any AuthProvider<T>

  /// A stream that updates with the current ``AuthState`` of this client instance.
  public var authStates: AsyncStream<AuthState<T>> {
    authStateEmitter.events
  }

  /// Creates a new instance of ``ConvexClientWithAuth``.
  ///
  /// - Parameters:
  ///   - deploymentUrl: The Convex backend URL to connect to; find it in the [dashboard](https://dashboard.convex.dev) Settings for your project
  ///   - authProvider: An instance that will handle the actual authentication duties.
  public init(deploymentUrl: String, authProvider: any AuthProvider<T>) {
    self.client = ConvexClient(deploymentUrl: deploymentUrl)
    self.authProvider = authProvider
  }

  init(ffiClient: MobileConvexClientProtocol, authProvider: any AuthProvider<T>) {
    self.client = ConvexClient(ffiClient: ffiClient)
    self.authProvider = authProvider
  }

  /// Subscribes to the query with the given `name` and streams decoded subscription updates.
  ///
  /// The upstream Convex subscription is canceled when the returned stream terminates.
  ///
  /// - Parameters:
  ///   - name: A value in `module:query_name` format that identifies the backend query.
  ///   - args: Optional arguments to send to the backend query function.
  ///   - output: The expected stream element type, useful when inference is not enough.
  public func stream<Value: Decodable & Sendable>(
    to name: String, with args: [String: ConvexValue?]? = nil, yielding output: Value.Type? = nil
  ) -> AsyncThrowingStream<Value, Error> {
    client.stream(to: name, with: args, yielding: output)
  }

  /// Executes the query with the given `name` and `args` and returns the decoded result.
  ///
  /// For queries that return `null`, call this as an optional type such as `String?`.
  ///
  /// - Parameters:
  ///   - name: A value in `module:query_name` format that identifies the backend query.
  ///   - args: Optional arguments to send to the backend query function.
  @discardableResult
  public func query<Value: Decodable>(_ name: String, with args: [String: ConvexValue?]? = nil)
    async throws -> Value
  {
    try await client.query(name, with: args)
  }

  /// Executes the mutation with the given `name` and `args` and returns the decoded result.
  ///
  /// For mutations that return `null`, call this as an optional type such as `String?`.
  ///
  /// - Parameters:
  ///   - name: A value in `module:mutation_name` format that identifies the backend mutation.
  ///   - args: Optional arguments to send to the backend mutation function.
  @discardableResult
  public func mutation<Value: Decodable>(_ name: String, with args: [String: ConvexValue?]? = nil)
    async throws -> Value
  {
    try await client.mutation(name, with: args)
  }

  /// Executes the action with the given `name` and `args` and returns the decoded result.
  ///
  /// For actions that return `null`, call this as an optional type such as `String?`.
  ///
  /// - Parameters:
  ///   - name: A value in `module:action_name` format that identifies the backend action.
  ///   - args: Optional arguments to send to the backend action function.
  @discardableResult
  public func action<Value: Decodable>(_ name: String, with args: [String: ConvexValue?]? = nil)
    async throws -> Value
  {
    try await client.action(name, with: args)
  }

  /// Streams websocket connection state changes from the underlying transport client.
  public func watchWebSocketStates() -> AsyncStream<ConvexWebSocketState> {
    client.watchWebSocketStates()
  }

  /// Triggers a UI driven login flow and updates the ``authState``.
  ///
  /// The ``authState`` is set to ``AuthState.loading`` immediately upon calling this method and
  /// will change to either ``AuthState.authenticated`` or ``AuthState.unauthenticated``
  /// depending on the result.
  @discardableResult
  public func login() async throws -> T {
    try await login(strategy: authProvider.login)
  }

  /// Triggers a cached, UI-less re-authentication flow using previously stored credentials and updates the
  /// ``authState``.
  ///
  /// If no credentials were previously stored, or if there is an error reusing stored credentials, the resulting
  /// ``authState`` willl be ``AuthState.unauthenticated``. If supported by the ``AuthProvider``,
  /// a call to ``login()`` should store another set of credentials upon successful authentication.
  ///
  /// The ``authState`` is set to ``AuthState.loading`` immediately upon calling this method and
  /// will change to either ``AuthState.authenticated`` or ``AuthState.unauthenticated``
  /// depending on the result.
  @discardableResult
  public func loginFromCache() async throws -> T {
    try await login(strategy: authProvider.loginFromCache)
  }

  /// Triggers a logout flow and updates the ``authState``.
  ///
  /// The ``authState`` will change to ``AuthState.unauthenticated`` if logout is successful.
  public func logout() async throws {
    await taskCoordinator.cancelAll()
    do {
      try await authProvider.logout()
      await authBridgeStore.set(nil)
      try await client.setAuthCallback(nil)
      authStateEmitter.send(.unauthenticated)
    } catch {
      authStateEmitter.send(.unauthenticated)
      throw error
    }
  }

  private func login(strategy: LoginStrategy) async throws -> T {
    authStateEmitter.send(.loading)
    let idTokenHandler = onIdTokenHandler()
    let bridge = AuthTokenProviderBridge(
      token: nil,
      getValidToken: {
        [authProvider, idTokenHandler] in
        let refreshData = try await authProvider.loginFromCache(
          onIdToken: idTokenHandler
        )
        return authProvider.extractIdToken(from: refreshData)
      }
    )
    await authBridgeStore.set(bridge)

    do {
      let authData = try await strategy(idTokenHandler)
      let token = authProvider.extractIdToken(from: authData)
      await bridge.updateToken(token)
      try await client.setAuthCallback(bridge)
      authStateEmitter.send(.authenticated(authData))
      return authData
    } catch {
      await authBridgeStore.set(nil)
      authStateEmitter.send(.unauthenticated)
      let loginError = error
      do {
        try await client.setAuthCallback(nil)
      } catch {
        throw loginError
      }
      throw loginError
    }
  }

  private func onIdTokenHandler() -> @Sendable (String?) -> Void {
    { [authBridgeStore, client, authStateEmitter, taskCoordinator] token in
      let task = Task {
        do {
          guard !Task.isCancelled else {
            return
          }

          if let token {
            if let bridge = await authBridgeStore.updateToken(token) {
              try await client.setAuthCallback(bridge)
            }
          } else {
            await authBridgeStore.set(nil)
            try await client.setAuthCallback(nil)
            authStateEmitter.send(.unauthenticated)
          }
        } catch {
          authStateEmitter.send(.unauthenticated)
        }
      }

      Task {
        await taskCoordinator.track(task)
      }
    }
  }

  private typealias LoginStrategy = (@Sendable @escaping (String?) -> Void) async throws -> T

  deinit {
    Task { [taskCoordinator] in
      await taskCoordinator.cancelAll()
    }
  }
}
