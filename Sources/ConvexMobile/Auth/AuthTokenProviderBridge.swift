import Foundation
@preconcurrency import UniFFI

actor AuthTokenProviderBridge: AuthTokenProvider {
  private var cachedToken: String?
  private var refreshTask: Task<String?, Error>?
  private let getValidToken: @Sendable () async throws -> String?

  init(token: String?, getValidToken: @escaping @Sendable () async throws -> String?) {
    self.cachedToken = token
    self.getValidToken = getValidToken
  }

  func fetchToken(forceRefresh: Bool) async throws -> String? {
    guard forceRefresh else {
      return cachedToken
    }

    if let refreshTask {
      return try await refreshTask.value
    }

    let task = Task {
      try await getValidToken()
    }
    refreshTask = task
    defer {
      refreshTask = nil
    }

    let freshToken = try await task.value
    cachedToken = freshToken
    return freshToken
  }

  func updateToken(_ token: String?) {
    cachedToken = token
  }
}
