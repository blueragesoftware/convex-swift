import Foundation

/// A type that supplies authentication credentials to ``ConvexClientWithAuth``.
///
/// The associated type is the provider-specific value returned after a successful login. For example, an app can
/// return its Clerk session, a user model, or another Sendable auth representation.
public protocol AuthProvider<AuthResult>: Sendable {
  associatedtype AuthResult

  /// Starts an interactive login flow.
  ///
  /// - Parameter onIdToken: A callback the provider invokes whenever it has a fresh JWT ID token. Pass `nil`
  ///   when the session becomes invalid.
  /// - Returns: Provider-specific authenticated user or session data.
  func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> AuthResult

  /// Logs out of the provider and clears provider-owned credentials.
  func logout() async throws

  /// Re-authenticates from provider-owned cached credentials without starting UI.
  ///
  /// - Parameter onIdToken: A callback the provider invokes whenever it has a fresh JWT ID token. Pass `nil`
  ///   when the cached session is invalid.
  /// - Returns: Provider-specific authenticated user or session data.
  func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> AuthResult

  /// Extracts the JWT ID token Convex should use from provider-specific auth data.
  func extractIdToken(from authResult: AuthResult) -> String
}
