import Foundation
import Testing

@testable import ConvexMobile
@testable import UniFFI

@Suite("Convex mobile client", .serialized)
struct ConvexMobileTests {
  @Test func subscribeResult() async throws {
    let client = ConvexMobile.ConvexClient(ffiClient: FakeMobileConvexClient())

    let result: Message = try await firstValue(from: client.stream(to: "foo"))

    #expect(result.id == "the_id")
    #expect(result.val == 42)
  }

  @Test func subscribeCanTrimDupeVals() async throws {
    let published = AsyncStream<Void>.makeStream()
    let client = ConvexMobile.ConvexClient(
      ffiClient: FakeMobileConvexClient(resultPublished: published.continuation))

    let streamTask = Task { () throws -> [Message] in
      var previousValue: Message?
      var result: [Message] = []
      for try await value in client.stream(to: "dupeVals", yielding: Message.self) {
        guard value != previousValue else {
          continue
        }

        previousValue = value
        result.append(value)
        if result.count == 1 {
          return result
        }
      }
      return result
    }

    _ = try await firstValue(from: published.stream)
    let result = try await streamTask.value

    #expect(result.count == 1)
  }

  @Test func subscribeOptionalResultWithPresentVal() async throws {
    let client = ConvexMobile.ConvexClient(ffiClient: FakeMobileConvexClient())

    let result: MessageWithOptionalVal? = try await firstValue(from: client.stream(to: "foo"))
    let value = try #require(result)

    #expect(value.id == "the_id")
    #expect(value.val == 42)
  }

  @Test func subscribeOptionalResultWithNullVal() async throws {
    let client = ConvexMobile.ConvexClient(ffiClient: FakeMobileConvexClient())

    let result: MessageWithOptionalVal? = try await firstValue(from: client.stream(to: "nullVal"))
    let value = try #require(result)

    #expect(value.id == "the_id")
    #expect(value.val == nil)
  }

  @Test func subscribeOptionalResultWithMissingVal() async throws {
    let client = ConvexMobile.ConvexClient(ffiClient: FakeMobileConvexClient())

    let result: MessageWithOptionalVal? = try await firstValue(from: client.stream(to: "missingVal"))
    let value = try #require(result)

    #expect(value.id == "the_id")
    #expect(value.val == nil)
  }

  @Test func missingSubscribeArgs() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClient(ffiClient: fakeFfiClient)

    let _: Message = try await firstValue(from: client.stream(to: "foo"))

    #expect(fakeFfiClient.subscriptionArgs == [:])
  }

  @Test func populatedSubscribeArgs() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClient(ffiClient: fakeFfiClient)

    let _: Message = try await firstValue(from: client.stream(
      to: "foo",
      with: [
        "aString": "bar", "aDouble": 42.0, "anInt": 42, "aNil": nil,
        "aDict": ["sub1": 1.0, "nested": ["ohmy": true] as [String: ConvexValue?]] as [String: ConvexValue?],
        "aList": [true, false, true, nil] as [ConvexValue?],
      ]
    ))

    #expect(fakeFfiClient.subscriptionArgs["aString"] == "\"bar\"")
    #expect(fakeFfiClient.subscriptionArgs["aDouble"] == "42")
    #expect(fakeFfiClient.subscriptionArgs["anInt"] == "{\"$integer\":\"KgAAAAAAAAA=\"}")
    #expect(fakeFfiClient.subscriptionArgs["aNil"] == "null")
    #expect(fakeFfiClient.subscriptionArgs["aDict"] == "{\"nested\":{\"ohmy\":true},\"sub1\":1}")
    #expect(fakeFfiClient.subscriptionArgs["aList"] == "[true,false,true,null]")
  }

  @Test func subscribeCancellation() async throws {
    let receivedValue = AsyncStream<Void>.makeStream()
    let ffiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClient(ffiClient: ffiClient)

    let streamTask = Task {
      for try await _: Message in client.stream(to: "foo") {
        receivedValue.continuation.yield()
        receivedValue.continuation.finish()
      }
    }

    _ = try await firstValue(from: receivedValue.stream)
    streamTask.cancel()
    _ = await streamTask.result

    #expect(ffiClient.cancellationCount == 1)
  }

  @Test func queryRoundTrip() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClient(ffiClient: fakeFfiClient)

    let message: Message = try await client.query("foo", with: ["anInt": 303])

    #expect(message.id == "the_id")
    #expect(message.val == 303)
  }

  @Test func mutationRoundTrip() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClient(ffiClient: fakeFfiClient)

    let message: Message = try await client.mutation("foo", with: ["anInt": 101])

    #expect(message.id == "the_id")
    #expect(message.val == 101)
  }

  @Test func voidMutation() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClient(ffiClient: fakeFfiClient)

    let _: String? = try await client.mutation("nullResult")

    #expect(fakeFfiClient.mutationCalls == ["nullResult"])
  }

  @Test func actionRoundTrip() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClient(ffiClient: fakeFfiClient)

    let message: Message = try await client.action("foo", with: ["anInt": Int.max])

    #expect(message.id == "the_id")
    #expect(message.val == Int.max)
  }

  @Test func voidAction() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClient(ffiClient: fakeFfiClient)

    let _: String? = try await client.action("nullResult")

    #expect(fakeFfiClient.actionCalls == ["nullResult"])
  }

  @Test func mutationTypeMismatchThrows() async throws {
    let client = ConvexMobile.ConvexClient(ffiClient: FakeMobileConvexClient())

    await #expect(throws: DecodingError.self) {
      let _: Message = try await client.mutation("typeMismatch")
    }
  }

  @Test func subscribeTypeMismatchSendsError() async throws {
    let client = ConvexMobile.ConvexClient(ffiClient: FakeMobileConvexClient())

    await #expect(throws: DecodingError.self) {
      let _: Message = try await firstValue(from: client.stream(to: "typeMismatch"))
    }
  }

  @Test func loginSetsAuthCallbackOnFfiClient() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClientWithAuth(
      ffiClient: fakeFfiClient, authProvider: FakeAuthProvider())

    let result = try await client.login()

    #expect(result == FakeAuthProvider.credentials)
    let authProvider = try #require(fakeFfiClient.authProvider)
    let token = try await authProvider.fetchToken(forceRefresh: false)
    #expect(token == "extracted: \(FakeAuthProvider.credentials)")
  }

  @Test func loginFromCacheSetsAuthCallbackOnFfiClient() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClientWithAuth(
      ffiClient: fakeFfiClient, authProvider: FakeAuthProvider())

    let result = try await client.loginFromCache()

    #expect(result == FakeAuthProvider.credentials)
    let authProvider = try #require(fakeFfiClient.authProvider)
    let token = try await authProvider.fetchToken(forceRefresh: false)
    #expect(token == "extracted: \(FakeAuthProvider.credentials)")
  }

  @Test func logoutClearsAuthCallbackOnFfiClient() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let client = ConvexMobile.ConvexClientWithAuth(
      ffiClient: fakeFfiClient, authProvider: FakeAuthProvider())

    try await client.login()
    #expect(fakeFfiClient.authProvider != nil)

    try await client.logout()

    #expect(fakeFfiClient.authProvider == nil)
  }

  @Test func loginUpdatesAuthState() async throws {
    let client = ConvexMobile.ConvexClientWithAuth(
      ffiClient: FakeMobileConvexClient(), authProvider: FakeAuthProvider())

    let authStateTask = Task { () -> String? in
      for await value in client.authStates {
        if case .authenticated(let creds) = value {
          return creds
        }
      }
      return nil
    }

    let result = try await client.login()
    let credentials = await authStateTask.value

    #expect(result == FakeAuthProvider.credentials)
    #expect(credentials == FakeAuthProvider.credentials)
  }

  @Test func forceRefreshCallsLoginFromCacheForFreshToken() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let fakeAuthProvider = FakeAuthProvider()
    let client = ConvexMobile.ConvexClientWithAuth(
      ffiClient: fakeFfiClient, authProvider: fakeAuthProvider)

    let result = try await client.login()
    #expect(result == FakeAuthProvider.credentials)

    let callCountAfterLogin = fakeAuthProvider.loginFromCacheCallCount
    let authProvider = try #require(fakeFfiClient.authProvider)
    let token = try await authProvider.fetchToken(forceRefresh: true)

    #expect(token == "extracted: \(FakeAuthProvider.credentials)")
    #expect(fakeAuthProvider.loginFromCacheCallCount == callCountAfterLogin + 1)
  }

  @Test func tokenRefreshUpdatesAuthCallback() async throws {
    let setAuthCallbackSignal = AsyncStream<Void>.makeStream()
    let fakeFfiClient = FakeMobileConvexClient()
    let fakeAuthProvider = FakeAuthProvider()
    let client = ConvexMobile.ConvexClientWithAuth(
      ffiClient: fakeFfiClient, authProvider: fakeAuthProvider)

    let result = try await client.login()
    #expect(result == FakeAuthProvider.credentials)

    let initialAuthProvider = try #require(fakeFfiClient.authProvider)
    let initialToken = try await initialAuthProvider.fetchToken(forceRefresh: false)
    #expect(initialToken == "extracted: \(FakeAuthProvider.credentials)")

    fakeFfiClient.setAuthCallbackSignal = setAuthCallbackSignal.continuation
    let refreshedToken = "refreshed_token_value"
    fakeAuthProvider.simulateTokenRefresh(newToken: refreshedToken)

    _ = try await firstValue(from: setAuthCallbackSignal.stream)

    let updatedAuthProvider = try #require(fakeFfiClient.authProvider)
    let updatedToken = try await updatedAuthProvider.fetchToken(forceRefresh: false)
    #expect(updatedToken == refreshedToken)
  }

  @Test func tokenRefreshWithNilSetsAuthStateToUnauthenticated() async throws {
    let fakeFfiClient = FakeMobileConvexClient()
    let fakeAuthProvider = FakeAuthProvider()
    let client = ConvexMobile.ConvexClientWithAuth(
      ffiClient: fakeFfiClient, authProvider: fakeAuthProvider)

    let authStateTask = Task { () -> Bool in
      var didBecomeUnauthenticated = false
      for await value in client.authStates {
        if case .unauthenticated = value {
          if didBecomeUnauthenticated {
            return true
          }
        } else if case .authenticated = value {
          didBecomeUnauthenticated = true
        }
      }
      return false
    }

    let result = try await client.login()
    #expect(result == FakeAuthProvider.credentials)

    fakeAuthProvider.simulateTokenRefresh(newToken: nil)
    let becameUnauthenticated = await authStateTask.value

    #expect(becameUnauthenticated)
    #expect(fakeFfiClient.authProvider == nil)
  }
}

private func firstValue<Element>(
  from stream: AsyncThrowingStream<Element, Error>
) async throws -> Element {
  var iterator = stream.makeAsyncIterator()
  guard let value = try await iterator.next() else {
    throw ClientError.InternalError(msg: "Expected stream value")
  }
  return value
}

private func firstValue<Element>(
  from stream: AsyncStream<Element>
) async throws -> Element {
  var iterator = stream.makeAsyncIterator()
  guard let value = await iterator.next() else {
    throw ClientError.InternalError(msg: "Expected stream value")
  }
  return value
}

final class FakeMobileConvexClient: UniFFI.MobileConvexClientProtocol, @unchecked Sendable {
  var cancellationCount = 0
  var subscriptionArgs: [String: String] = [:]
  var mutationCalls: [String] = []
  var actionCalls: [String] = []
  var queryCalls: [String] = []
  var auth: String? = nil
  var authProvider: (any AuthTokenProvider)? = nil
  var resultPublished: AsyncStream<Void>.Continuation?
  var setAuthSignal: AsyncStream<Void>.Continuation?
  var setAuthCallbackSignal: AsyncStream<Void>.Continuation?

  init(initialAuth: String? = nil, resultPublished: AsyncStream<Void>.Continuation? = nil) {
    self.auth = initialAuth
    self.resultPublished = resultPublished
  }

  func action(name: String, args: [String: String]) async throws -> String {
    actionCalls.append(name)
    if name == "nullResult" {
      return "null"
    }
    if name == "typeMismatch" {
      return "\"just a plain string\""
    }
    guard let receivedConvexInt = args["anInt"] else {
      throw ClientError.InternalError(msg: "Missing anInt")
    }
    return "{\"_id\": \"the_id\", \"val\": \(receivedConvexInt), \"extra\": null}"
  }

  func mutation(name: String, args: [String: String]) async throws -> String {
    mutationCalls.append(name)
    if name == "nullResult" {
      return "null"
    }
    if name == "typeMismatch" {
      return "\"just a plain string\""
    }
    guard let receivedConvexInt = args["anInt"] else {
      throw ClientError.InternalError(msg: "Missing anInt")
    }
    return "{\"_id\": \"the_id\", \"val\": \(receivedConvexInt), \"extra\": null}"
  }

  func query(name: String, args: [String: String]) async throws -> String {
    queryCalls.append(name)
    let receivedConvexInt = args["anInt"] ?? "{\"$integer\":\"KgAAAAAAAAA=\"}"
    return "{\"_id\": \"the_id\", \"val\": \(receivedConvexInt), \"extra\": null}"
  }

  func setAuth(token: String?) async throws {
    auth = token
    setAuthSignal?.yield()
    setAuthSignal?.finish()
  }

  func setAuthCallback(provider: (any AuthTokenProvider)?) async throws {
    authProvider = provider
    setAuthCallbackSignal?.yield()
    setAuthCallbackSignal?.finish()
  }

  func subscribe(name: String, args: [String: String], subscriber: any UniFFI.QuerySubscriber)
    async throws -> UniFFI.SubscriptionHandle
  {
    subscriptionArgs = args
    let subscriberBox = QuerySubscriberBox(subscriber)
    let _ = Task {
      try await Task.sleep(nanoseconds: UInt64(0.05 * 1_000_000_000))
      if name == "typeMismatch" {
        subscriberBox.subscriber.onUpdate(
          value: "\"just a plain string\"")
      } else if name == "missingVal" {
        subscriberBox.subscriber.onUpdate(
          value: "{\"_id\": \"the_id\", \"extra\": null}")
      } else if name == "nullVal" {
        subscriberBox.subscriber.onUpdate(
          value: "{\"_id\": \"the_id\", \"val\": null, \"extra\": null}")
      } else {
        subscriberBox.subscriber.onUpdate(
          value: "{\"_id\": \"the_id\", \"val\": {\"$integer\":\"KgAAAAAAAAA=\"}, \"extra\": null}")
        if name == "dupeVals" {
          subscriberBox.subscriber.onUpdate(
            value:
              "{\"_id\": \"the_id\", \"val\": {\"$integer\":\"KgAAAAAAAAA=\"}, \"extra\": null}")
        }
      }
      resultPublished?.yield()
      resultPublished?.finish()
    }
    return FakeSubscriptionHandle(client: self)
  }
}

private final class QuerySubscriberBox: @unchecked Sendable {
  let subscriber: any UniFFI.QuerySubscriber

  init(_ subscriber: any UniFFI.QuerySubscriber) {
    self.subscriber = subscriber
  }
}

final class FakeAuthProvider: AuthProvider, @unchecked Sendable {
  static let credentials = "credentials, yo"

  private var storedOnIdToken: (@Sendable (String?) -> Void)?
  var loginFromCacheCallCount = 0

  func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
    loginFromCacheCallCount += 1
    storedOnIdToken = onIdToken
    onIdToken("extracted: \(Self.credentials)")
    return Self.credentials
  }

  func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
    storedOnIdToken = onIdToken
    onIdToken("extracted: \(Self.credentials)")
    return Self.credentials
  }

  func logout() async throws {}

  func extractIdToken(from authResult: String) -> String {
    return "extracted: \(authResult)"
  }

  func simulateTokenRefresh(newToken: String?) {
    storedOnIdToken?(newToken)
  }
}

class FakeSubscriptionHandle: UniFFI.SubscriptionHandle {
  let client: FakeMobileConvexClient

  init(client: FakeMobileConvexClient) {
    self.client = client
    super.init(noPointer: UniFFI.SubscriptionHandle.NoPointer())
  }

  required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
    fatalError("init(unsafeFromRawPointer:) has not been implemented")
  }

  override func cancel() {
    self.client.cancellationCount += 1
  }
}

private struct MessageWithOptionalVal: Decodable, Sendable {
  let id: String
  var val: Int?

  enum CodingKeys: String, CodingKey {
    case id = "_id"
    case val
  }
}

private struct Message: Decodable, Equatable, Sendable {
  let id: String
  var val: Int

  enum CodingKeys: String, CodingKey {
    case id = "_id"
    case val
  }
}
