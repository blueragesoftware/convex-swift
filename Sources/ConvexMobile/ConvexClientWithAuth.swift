import Foundation
@preconcurrency import UniFFI

/// Authentication states that can be experienced when using an ``AuthProvider`` with
/// ``ConvexClientWithAuth``.
public enum AuthState<T: Sendable>: Sendable {
  /// Represents an authenticated user.
  ///
  /// Contains authentication data from the associated ``AuthProvider``.
  case authenticated(T)
  /// Represents an unauthenticated user.
  case unauthenticated
  /// Represents an ongoing authentication attempt.
  case loading
}

/// An authentication provider, used with ``ConvexClientWithAuth``.
///
/// The generic type `T` is the data returned by the provider upon a successful authentication attempt.
public protocol AuthProvider<T>: Sendable {
  associatedtype T

  /// Trigger a login flow, which might launch a new UI/screen.
  ///
  /// - Parameter onIdToken: A callback to invoke with a fresh JWT ID token. The auth provider should store
  ///   this callback and invoke it whenever a new token is available (e.g., on token refresh).
  ///   Call with `nil` if the session becomes invalid (e.g., token refresh fails).
  func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> T

  /// Trigger a logout flow, which might launch a new UI/screen.
  func logout() async throws

  /// Trigger a cached, UI-less re-authentication using stored credentials from a previous ``login()``.
  ///
  /// For OAuth providers, this is a good place to check token validity and perform a refresh if necessary
  /// before returning the auth data as``T``.
  ///
  /// - Parameter onIdToken: A callback to invoke with a fresh JWT ID token. The auth provider should store
  ///   this callback and invoke it whenever a new token is available (e.g., on token refresh).
  ///   Call with `nil` if the session becomes invalid (e.g., token refresh fails).
  func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void)
    async throws -> T

  /// Extracts a [JWT ID token](https://openid.net/specs/openid-connect-core-1_0.html#IDToken)
  /// from the `authResult`.
  func extractIdToken(from authResult: T) -> String
}

/// Like ``ConvexClient``, but supports integration with an authentication provider via ``AuthProvider``.
///
/// The generic parameter `T` matches the type of data returned by the ``AuthProvider`` upon successful
/// authentication.
public class ConvexClientWithAuth<T: Sendable>: ConvexClient, @unchecked Sendable {
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
    self.authProvider = authProvider
    super.init(deploymentUrl: deploymentUrl)
  }

  init(ffiClient: MobileConvexClientProtocol, authProvider: any AuthProvider<T>) {
    self.authProvider = authProvider
    super.init(ffiClient: ffiClient)
  }

  /// Triggers a UI driven login flow and updates the ``authState``.
  ///
  /// The ``authState`` is set to ``AuthState.loading`` immediately upon calling this method and
  /// will change to either ``AuthState.authenticated`` or ``AuthState.unauthenticated``
  /// depending on the result.
  public func login() async -> Result<T, Error> {
    await login(strategy: authProvider.login)
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
  public func loginFromCache() async -> Result<T, Error> {
    await login(strategy: authProvider.loginFromCache)
  }

  /// Triggers a logout flow and updates the ``authState``.
  ///
  /// The ``authState`` will change to ``AuthState.unauthenticated`` if logout is successful.
  public func logout() async -> Result<Void, Error> {
    await taskCoordinator.cancelAll()
    do {
      try await authProvider.logout()
      await authBridgeStore.set(nil)
      try await ffiClient.setAuthCallback(provider: nil)
      authStateEmitter.send(.unauthenticated)
      return .success(())
    } catch {
      authStateEmitter.send(.unauthenticated)
      return .failure(error)
    }
  }

  private func login(strategy: LoginStrategy) async -> Result<T, Error> {
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
      try await ffiClient.setAuthCallback(provider: bridge)
      authStateEmitter.send(.authenticated(authData))
      return Result.success(authData)
    } catch {
      await authBridgeStore.set(nil)
      authStateEmitter.send(.unauthenticated)
      let loginError = error
      do {
        try await ffiClient.setAuthCallback(provider: nil)
      } catch {
        return Result.failure(loginError)
      }
      return Result.failure(loginError)
    }
  }

  private func onIdTokenHandler() -> @Sendable (String?) -> Void {
    { [authBridgeStore, ffiClient, authStateEmitter, taskCoordinator] token in
      let task = Task {
        do {
          guard !Task.isCancelled else {
            return
          }

          if let token {
            if let bridge = await authBridgeStore.updateToken(token) {
              try await ffiClient.setAuthCallback(provider: bridge)
            }
          } else {
            await authBridgeStore.set(nil)
            try await ffiClient.setAuthCallback(provider: nil)
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

private actor AuthTokenProviderBridge: AuthTokenProvider {
  private var cachedToken: String?
  private var getValidToken: @Sendable () async throws -> String?

  init(token: String?, getValidToken: @escaping @Sendable () async throws -> String?) {
    self.cachedToken = token
    self.getValidToken = getValidToken
  }

  func fetchToken(forceRefresh: Bool) async throws -> String? {
    if forceRefresh, let freshToken = try await getValidToken() {
      cachedToken = freshToken
    }
    return cachedToken
  }

  func updateToken(_ token: String?) {
    cachedToken = token
  }
}

private actor AuthBridgeStore {
  private var bridge: AuthTokenProviderBridge?

  func set(_ bridge: AuthTokenProviderBridge?) {
    self.bridge = bridge
  }

  func updateToken(_ token: String?) async -> AuthTokenProviderBridge? {
    await bridge?.updateToken(token)
    return bridge
  }

  func current() -> AuthTokenProviderBridge? {
    bridge
  }
}
