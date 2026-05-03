import Foundation

actor AuthBridgeStore {
  private var bridge: AuthTokenProviderBridge?

  func set(_ bridge: AuthTokenProviderBridge?) {
    self.bridge = bridge
  }

  func updateToken(_ token: String?) async -> AuthTokenProviderBridge? {
    await bridge?.updateToken(token)
    return bridge
  }
}
