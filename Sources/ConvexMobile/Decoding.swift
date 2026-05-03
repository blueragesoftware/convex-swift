//
//  Decoding.swift
//  ConvexMobile
//
//  Created by Christian Wyglendowski on 10/1/24.
//

import Foundation

private enum ConvexTypeKey: String, CodingKey {
  case integer = "$integer"
  case float = "$float"
}

private enum ConvexDecoding {
  static func decodeInteger<IntegerType: FixedWidthInteger>(
    _ type: IntegerType.Type,
    from base64String: String,
    codingPath: [CodingKey]
  ) throws -> IntegerType {
    let data = try decodeBase64Bytes(
      base64String,
      expectedByteCount: MemoryLayout<Int64>.size,
      codingPath: codingPath
    )

    let decoded = data.withUnsafeBytes { rawPtr in
      rawPtr.load(as: Int64.self)
    }

    guard let value = IntegerType(exactly: decoded) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: codingPath,
          debugDescription: "\(decoded) cannot be represented as \(IntegerType.self)."
        )
      )
    }
    return value
  }

  static func decodeFloat<FloatingPointType: BinaryFloatingPoint>(
    _ type: FloatingPointType.Type,
    from base64String: String,
    codingPath: [CodingKey]
  ) throws -> FloatingPointType {
    let data = try decodeBase64Bytes(
      base64String,
      expectedByteCount: MemoryLayout<Double>.size,
      codingPath: codingPath
    )

    return data.withUnsafeBytes { rawPtr in
      let decoded = rawPtr.load(as: Double.self)
      return FloatingPointType(decoded)
    }
  }

  private static func decodeBase64Bytes(
    _ base64String: String,
    expectedByteCount: Int,
    codingPath: [CodingKey]
  ) throws -> Data {
    guard let data = Data(base64Encoded: base64String) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: codingPath,
          debugDescription: "Expected a base64-encoded Convex numeric payload."
        )
      )
    }

    guard data.count == expectedByteCount else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: codingPath,
          debugDescription: "Expected \(expectedByteCount) bytes, received \(data.count)."
        )
      )
    }

    return data
  }
}

@propertyWrapper
public struct ConvexInt<IntegerType: FixedWidthInteger & Sendable>: Decodable, Equatable, Sendable {
  public var wrappedValue: IntegerType

  public init(wrappedValue: IntegerType) {
    self.wrappedValue = wrappedValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: ConvexTypeKey.self)
    let b64int = try container.decode(String.self, forKey: .integer)
    self.wrappedValue = try ConvexDecoding.decodeInteger(
      IntegerType.self,
      from: b64int,
      codingPath: container.codingPath + [ConvexTypeKey.integer]
    )
  }
}

@propertyWrapper
public struct OptionalConvexInt<IntegerType: FixedWidthInteger & Sendable>: Decodable, Equatable, Sendable {
  public var wrappedValue: IntegerType?

  public init(wrappedValue: IntegerType?) {
    self.wrappedValue = wrappedValue
  }

  public init(from decoder: Decoder) throws {
    let singleValueContainer = try decoder.singleValueContainer()
    guard !singleValueContainer.decodeNil() else {
      self.wrappedValue = nil
      return
    }

    let container = try decoder.container(keyedBy: ConvexTypeKey.self)
    let b64int = try container.decode(String.self, forKey: .integer)
    self.wrappedValue = try ConvexDecoding.decodeInteger(
      IntegerType.self,
      from: b64int,
      codingPath: container.codingPath + [ConvexTypeKey.integer]
    )
  }
}

@propertyWrapper
public struct ConvexFloat<FloatingPointType: BinaryFloatingPoint & Decodable & Sendable>: Decodable, Equatable,
  Sendable
{
  public var wrappedValue: FloatingPointType

  public init(wrappedValue: FloatingPointType) {
    self.wrappedValue = wrappedValue
  }

  public init(from decoder: Decoder) throws {
    do {
      let container = try decoder.container(keyedBy: ConvexTypeKey.self)
      let b64float = try container.decode(String.self, forKey: .float)
      self.wrappedValue = try ConvexDecoding.decodeFloat(
        FloatingPointType.self,
        from: b64float,
        codingPath: container.codingPath + [ConvexTypeKey.float]
      )
    } catch DecodingError.typeMismatch(_, _) {
      self.wrappedValue = try decoder.singleValueContainer().decode(FloatingPointType.self)
    } catch DecodingError.valueNotFound(_, _) {
      self.wrappedValue = try decoder.singleValueContainer().decode(FloatingPointType.self)
    } catch DecodingError.keyNotFound(_, _) {
      self.wrappedValue = try decoder.singleValueContainer().decode(FloatingPointType.self)
    }
  }
}

@propertyWrapper
public struct OptionalConvexFloat<FloatingPointType: BinaryFloatingPoint & Decodable & Sendable>: Decodable,
  Equatable, Sendable
{
  public var wrappedValue: FloatingPointType?

  public init(wrappedValue: FloatingPointType?) {
    self.wrappedValue = wrappedValue
  }

  public init(from decoder: Decoder) throws {
    let singleValueContainer = try decoder.singleValueContainer()
    guard !singleValueContainer.decodeNil() else {
      self.wrappedValue = nil
      return
    }

    do {
      let container = try decoder.container(keyedBy: ConvexTypeKey.self)
      let b64float = try container.decode(String.self, forKey: .float)
      self.wrappedValue = try ConvexDecoding.decodeFloat(
        FloatingPointType.self,
        from: b64float,
        codingPath: container.codingPath + [ConvexTypeKey.float]
      )
    } catch DecodingError.typeMismatch(_, _) {
      self.wrappedValue = try singleValueContainer.decode(FloatingPointType.self)
    } catch DecodingError.valueNotFound(_, _) {
      self.wrappedValue = try singleValueContainer.decode(FloatingPointType.self)
    } catch DecodingError.keyNotFound(_, _) {
      self.wrappedValue = try singleValueContainer.decode(FloatingPointType.self)
    }
  }
}

// This allows for decoding OptionalConvex[Int|Float] when the associated key isn't present in the payload.
extension KeyedDecodingContainer {
  public func decode<T>(_ type: OptionalConvexInt<T>.Type, forKey key: Self.Key) throws
    -> OptionalConvexInt<T>
  {
    return try decodeIfPresent(type, forKey: key) ?? OptionalConvexInt(wrappedValue: nil)
  }

  public func decode<T>(_ type: OptionalConvexFloat<T>.Type, forKey key: Self.Key) throws
    -> OptionalConvexFloat<T>
  {
    return try decodeIfPresent(type, forKey: key) ?? OptionalConvexFloat(wrappedValue: nil)
  }
}
