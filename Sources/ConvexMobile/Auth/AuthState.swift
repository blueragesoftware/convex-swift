import Foundation

/// Authentication state emitted by ``ConvexClientWithAuth/authStates``.
public enum AuthState<AuthResult: Sendable>: Sendable {
  /// Authentication completed successfully.
  case authenticated(AuthResult)

  /// No authenticated session is currently available.
  case unauthenticated

  /// Authentication is currently in progress.
  case loading
}
