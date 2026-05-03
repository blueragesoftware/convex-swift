//
//  IntegrationTests.swift
//  ConvexMobile
//
//  Created by Christian Wyglendowski on 10/1/24.
//

import ConvexMobile
import Testing

private let deploymentUrl = "https://curious-lynx-309.convex.cloud"

private func firstValue<Element>(
  from stream: AsyncThrowingStream<Element, Error>
) async throws -> Element {
  var iterator = stream.makeAsyncIterator()
  guard let value = try await iterator.next() else {
    throw ClientError.InternalError(msg: "Expected stream value")
  }
  return value
}

@Suite(.serialized) struct Test {
  init() async throws {
    let client = ConvexClient(deploymentUrl: deploymentUrl)
    let _: String? = try await client.mutation("messages:clearAll")
  }

  @Test func test_empty_subscribe() async throws {
    let client = ConvexClient(deploymentUrl: deploymentUrl)
    let messages: [Message]? = try await firstValue(from: client.stream(to: "messages:list"))
    let requiredMessages = try #require(messages)
    #expect(requiredMessages == [])
  }

  @Test func test_convex_error_in_subscription() async throws {
    let client = ConvexClient(deploymentUrl: deploymentUrl)
    await #expect(throws: ClientError.ConvexError(data: "\"forced error data\"")) {
      let _: [Message]? = try await firstValue(from: client.stream(
        to: "messages:list",
        with: ["forceError": true]
      ))
    }
  }

  @Test func test_convex_error_in_action() async throws {
    let client = ConvexClient(deploymentUrl: deploymentUrl)
    await #expect(throws: ClientError.ConvexError(data: "\"forced error data\"")) {
      let _: String? = try await client.action("messages:forceActionError")
    }
  }

  @Test func test_convex_error_in_mutation() async throws {
    let client = ConvexClient(deploymentUrl: deploymentUrl)
    await #expect(throws: ClientError.ConvexError(data: "\"forced error data\"")) {
      let _: String? = try await client.mutation("messages:forceMutationError")
    }
  }

  @Test func send_and_receive_one_message() async throws {
    let clientA = ConvexClient(deploymentUrl: deploymentUrl)
    let clientB = ConvexClient(deploymentUrl: deploymentUrl)

    let _: String? = try await clientB.mutation(
      "messages:send", with: ["author": "Client B", "body": "Test 123"])

    let messages: [Message]? = try await firstValue(from: clientA.stream(to: "messages:list"))
    let requiredMessages = try #require(messages)
    #expect(requiredMessages == [Message(author: "Client B", body: "Test 123")])
  }

  @Test func send_and_receive_multiple_messages() async throws {
    let clientA = ConvexClient(deploymentUrl: deploymentUrl)
    let clientB = ConvexClient(deploymentUrl: deploymentUrl)

    let ready = AsyncStream<Void>.makeStream()
    let receiveTask = Task { () throws -> [[Message]] in
      var receivedMessages: [[Message]] = []
      for try await messages in clientA.stream(to: "messages:list", yielding: [Message]?.self) {
        receivedMessages.append(messages ?? [])
        if receivedMessages.count == 1 {
          ready.continuation.yield()
          ready.continuation.finish()
        }
        if receivedMessages.count == 4 {
          break
        }
      }
      return receivedMessages
    }

    for await _ in ready.stream {
      break
    }
    for i in 1...3 {
      let _: String? = try await clientB.mutation(
        "messages:send", with: ["author": "Client B", "body": "Message \(i)"])
    }

    let receivedMessages = try await receiveTask.value

    try #require(receivedMessages.count == 4)
    #expect(receivedMessages[0] == [])
    #expect(receivedMessages[1] == [Message(author: "Client B", body: "Message 1")])
    #expect(
      receivedMessages[2] == [
        Message(author: "Client B", body: "Message 1"),
        Message(author: "Client B", body: "Message 2"),
      ])
    #expect(
      receivedMessages[3] == [
        Message(author: "Client B", body: "Message 1"),
        Message(author: "Client B", body: "Message 2"),
        Message(author: "Client B", body: "Message 3"),
      ])
  }

  @Test func can_round_trip_max_value_args() async throws {
    let client = ConvexClient(deploymentUrl: deploymentUrl)
    let maxValues = NumericValues(
      anInt64: Int64.max, aFloat64: Double.greatestFiniteMagnitude,
      jsNumber: Double.greatestFiniteMagnitude, anInt32: Int32.max,
      aFloat32: Float32.greatestFiniteMagnitude)

    let result: NumericValues = try await client.action(
      "messages:echoValidatedArgs", with: maxValues.toArgs())

    #expect(result == maxValues)
  }

  @Test func can_round_trip_special_floats() async throws {
    let client = ConvexClient(deploymentUrl: deploymentUrl)
    let specialFloats = SpecialFloats()
    let result: SpecialFloats = try await client.action(
      "messages:echoArgs", with: specialFloats.toArgs())

    #expect(result.f32Nan.isNaN)
    #expect(result.f32NegInf == specialFloats.f32NegInf)
    #expect(result.f32PosInf == specialFloats.f32PosInf)
    #expect(result.f64Nan.isNaN)
    #expect(result.f64NegInf == specialFloats.f64NegInf)
    #expect(result.f64PosInf == specialFloats.f64PosInf)
  }

  @Test func can_receive_numbers() async throws {
    let client = ConvexClient(deploymentUrl: deploymentUrl)
    let result: NumericValues = try await client.action("messages:numbers")
    let expected = NumericValues(
      anInt64: 100, aFloat64: 100.0, jsNumber: 100.0, anInt32: 100, aFloat32: 100.0)
    #expect(result == expected)
    #expect(result.aPlainInt == 100)
  }

  @Test func can_receive_null_and_missing_float64_values() async throws {
    let client = ConvexClient(deploymentUrl: deploymentUrl)
    let result: NullableFloats = try await client.action(
      "messages:echoArgs", with: ["aNullableDouble": nil])
    #expect(result == NullableFloats())
  }
  
  @Test func can_observe_websocket_state() async throws {
    let client = ConvexClient(deploymentUrl: deploymentUrl)

    let receiveTask = Task { () -> [ConvexWebSocketState] in
      var states: [ConvexWebSocketState] = []
      for await state in client.watchWebSocketStates() {
        states.append(state)
        if states.count == 2 {
          break
        }
      }
      return states
    }
    
    let _: String? = try await client.mutation("messages:clearAll")

    let states = await receiveTask.value
    
    try #require(states.count == 2)
    #expect(states == [.connecting, .connected])
  }
}

private struct Message: Decodable, Equatable, Sendable {
  let author: String
  let body: String
}

private struct NumericValues: Decodable, Equatable, Sendable {
  init(anInt64: Int64, aFloat64: Float64, jsNumber: Double, anInt32: Int32, aFloat32: Float32) {
    self.anInt64 = anInt64
    self.aFloat64 = aFloat64
    self.jsNumber = jsNumber
    self.anInt32 = anInt32
    self.aFloat32 = aFloat32
  }

  @ConvexInt
  var anInt64: Int64
  @ConvexFloat
  var aFloat64: Float64
  @ConvexFloat
  private var jsNumber: Double
  @ConvexInt
  var anInt32: Int32
  @ConvexFloat
  var aFloat32: Float32

  enum CodingKeys: String, CodingKey {
    case anInt64
    case aFloat64
    case jsNumber = "aPlainInt"
    case anInt32
    case aFloat32
  }

  func toArgs() -> [String: ConvexEncodable] {
    [
      "anInt64": anInt64,
      "aFloat64": aFloat64,
      "aPlainInt": jsNumber,
      "anInt32": anInt32,
      "aFloat32": aFloat32,
    ]
  }

  // Expose the JavaScript number value as an Int.
  var aPlainInt: Int { Int(jsNumber) }
}

private struct SpecialFloats: Decodable, Equatable, Sendable {
  @ConvexFloat
  var f64Nan: Float64 = Float64.nan
  @ConvexFloat
  var f64NegInf: Double = -Double.infinity
  @ConvexFloat
  var f64PosInf: Double = Double.infinity
  @ConvexFloat
  var f32Nan: Float32 = Float32.nan
  @ConvexFloat
  var f32NegInf: Float32 = -Float32.infinity
  @ConvexFloat
  var f32PosInf: Float = Float.infinity

  func toArgs() -> [String: ConvexEncodable] {
    [
      "f64Nan": f64Nan,
      "f64NegInf": f64NegInf,
      "f64PosInf": f64PosInf,
      "f32Nan": f32Nan,
      "f32NegInf": f32NegInf,
      "f32PosInf": f32PosInf,
    ]
  }
}

private struct NullableFloats: Decodable, Equatable, Sendable {
  @OptionalConvexFloat
  var aNullableDouble: Double?
  @OptionalConvexFloat
  var aMissingDouble: Double?
}
