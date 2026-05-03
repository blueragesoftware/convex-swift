import Foundation

private enum ConvexTypeKey {
  static let integer = "$integer"
  static let float = "$float"
}

public enum ConvexDecodingError: Error, Equatable {
  case invalidJSON(String)
}

/// Decodes Convex JSON payloads into plain Swift `Decodable` models.
///
/// Convex tagged numeric payloads, such as `$integer` and `$float`, are decoded directly into Swift integer
/// and floating-point properties. User models do not need Convex-specific property wrappers.
public struct ConvexDecoder: Sendable {
  public init() {}

  /// Decodes a Convex JSON string into the requested Swift type.
  public func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    let data = Data(json.utf8)
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw ConvexDecodingError.invalidJSON(json)
    }

    return try T(from: ConvexValueDecoder(value: object, codingPath: []))
  }
}

private struct ConvexValueDecoder: Decoder {
  let value: Any
  let codingPath: [CodingKey]
  var userInfo: [CodingUserInfoKey: Any] { [:] }

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard let object = value as? [String: Any] else {
      throw typeMismatch([String: Any].self, value: value, codingPath: codingPath)
    }

    return KeyedDecodingContainer(ConvexKeyedDecodingContainer<Key>(object: object, codingPath: codingPath))
  }

  func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    guard let array = value as? [Any] else {
      throw typeMismatch([Any].self, value: value, codingPath: codingPath)
    }

    return ConvexUnkeyedDecodingContainer(values: array, codingPath: codingPath)
  }

  func singleValueContainer() throws -> SingleValueDecodingContainer {
    ConvexSingleValueDecodingContainer(value: value, codingPath: codingPath)
  }
}

private struct ConvexKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let object: [String: Any]
  let codingPath: [CodingKey]
  var allKeys: [Key] { object.keys.compactMap(Key.init(stringValue:)) }

  func contains(_ key: Key) -> Bool {
    object[key.stringValue] != nil
  }

  func decodeNil(forKey key: Key) throws -> Bool {
    guard let value = object[key.stringValue] else {
      return true
    }

    return value is NSNull
  }

  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: String.Type, forKey key: Key) throws -> String {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
    try decodeValue(type, forKey: key)
  }

  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
    try decodeValue(type, forKey: key)
  }

  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    try decodeValue(type, forKey: key)
  }

  func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type,
    forKey key: Key
  ) throws -> KeyedDecodingContainer<NestedKey> {
    try decoder(forKey: key).container(keyedBy: type)
  }

  func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
    try decoder(forKey: key).unkeyedContainer()
  }

  func superDecoder() throws -> Decoder {
    ConvexValueDecoder(value: object, codingPath: codingPath)
  }

  func superDecoder(forKey key: Key) throws -> Decoder {
    try decoder(forKey: key)
  }

  private func decodeValue<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    try T(from: decoder(forKey: key))
  }

  private func decoder(forKey key: Key) throws -> ConvexValueDecoder {
    guard let value = object[key.stringValue] else {
      throw DecodingError.keyNotFound(
        key,
        DecodingError.Context(codingPath: codingPath, debugDescription: "No value for key \(key.stringValue).")
      )
    }

    return ConvexValueDecoder(value: value, codingPath: codingPath + [key])
  }
}

private struct ConvexUnkeyedDecodingContainer: UnkeyedDecodingContainer {
  let values: [Any]
  let codingPath: [CodingKey]
  var currentIndex = 0
  var count: Int? { values.count }
  var isAtEnd: Bool { currentIndex >= values.count }

  mutating func decodeNil() throws -> Bool {
    guard !isAtEnd else {
      throw valueNotFound(Any.self, codingPath: codingPath)
    }

    if values[currentIndex] is NSNull {
      currentIndex += 1
      return true
    }

    return false
  }

  mutating func decode(_ type: Bool.Type) throws -> Bool { try decodeValue(type) }
  mutating func decode(_ type: String.Type) throws -> String { try decodeValue(type) }
  mutating func decode(_ type: Double.Type) throws -> Double { try decodeValue(type) }
  mutating func decode(_ type: Float.Type) throws -> Float { try decodeValue(type) }
  mutating func decode(_ type: Int.Type) throws -> Int { try decodeValue(type) }
  mutating func decode(_ type: Int8.Type) throws -> Int8 { try decodeValue(type) }
  mutating func decode(_ type: Int16.Type) throws -> Int16 { try decodeValue(type) }
  mutating func decode(_ type: Int32.Type) throws -> Int32 { try decodeValue(type) }
  mutating func decode(_ type: Int64.Type) throws -> Int64 { try decodeValue(type) }
  mutating func decode(_ type: UInt.Type) throws -> UInt { try decodeValue(type) }
  mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeValue(type) }
  mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeValue(type) }
  mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeValue(type) }
  mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeValue(type) }
  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try decodeValue(type) }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type
  ) throws -> KeyedDecodingContainer<NestedKey> {
    try nextDecoder().container(keyedBy: type)
  }

  mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
    try nextDecoder().unkeyedContainer()
  }

  mutating func superDecoder() throws -> Decoder {
    try nextDecoder()
  }

  private mutating func decodeValue<T: Decodable>(_ type: T.Type) throws -> T {
    try T(from: nextDecoder())
  }

  private mutating func nextDecoder() throws -> ConvexValueDecoder {
    guard !isAtEnd else {
      throw valueNotFound(Any.self, codingPath: codingPath)
    }

    let indexKey = ConvexIndexKey(index: currentIndex)
    let decoder = ConvexValueDecoder(value: values[currentIndex], codingPath: codingPath + [indexKey])
    currentIndex += 1
    return decoder
  }
}

private struct ConvexSingleValueDecodingContainer: SingleValueDecodingContainer {
  let value: Any
  let codingPath: [CodingKey]

  func decodeNil() -> Bool {
    value is NSNull
  }

  func decode(_ type: Bool.Type) throws -> Bool {
    guard let value = value as? Bool else {
      throw typeMismatch(type, value: value, codingPath: codingPath)
    }
    return value
  }

  func decode(_ type: String.Type) throws -> String {
    guard let value = value as? String else {
      throw typeMismatch(type, value: value, codingPath: codingPath)
    }
    return value
  }

  func decode(_ type: Double.Type) throws -> Double {
    try decodeFloat(type)
  }

  func decode(_ type: Float.Type) throws -> Float {
    Float(try decodeFloat(Double.self))
  }

  func decode(_ type: Int.Type) throws -> Int {
    try decodeInteger(type)
  }

  func decode(_ type: Int8.Type) throws -> Int8 {
    try decodeInteger(type)
  }

  func decode(_ type: Int16.Type) throws -> Int16 {
    try decodeInteger(type)
  }

  func decode(_ type: Int32.Type) throws -> Int32 {
    try decodeInteger(type)
  }

  func decode(_ type: Int64.Type) throws -> Int64 {
    try decodeInteger(type)
  }

  func decode(_ type: UInt.Type) throws -> UInt {
    try decodeInteger(type)
  }

  func decode(_ type: UInt8.Type) throws -> UInt8 {
    try decodeInteger(type)
  }

  func decode(_ type: UInt16.Type) throws -> UInt16 {
    try decodeInteger(type)
  }

  func decode(_ type: UInt32.Type) throws -> UInt32 {
    try decodeInteger(type)
  }

  func decode(_ type: UInt64.Type) throws -> UInt64 {
    try decodeInteger(type)
  }

  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try T(from: ConvexValueDecoder(value: value, codingPath: codingPath))
  }

  private func decodeInteger<Integer: FixedWidthInteger>(_ type: Integer.Type) throws -> Integer {
    let int64Value: Int64
    if let taggedInteger = taggedValue(for: ConvexTypeKey.integer) {
      int64Value = try decodeInt64(from: taggedInteger)
    } else if let number = value as? NSNumber, !isBool(number) {
      int64Value = number.int64Value
    } else {
      throw typeMismatch(type, value: value, codingPath: codingPath)
    }

    guard let value = Integer(exactly: int64Value) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: codingPath,
          debugDescription: "\(int64Value) cannot be represented as \(Integer.self)."
        )
      )
    }
    return value
  }

  private func decodeFloat<FloatingPoint: BinaryFloatingPoint>(_ type: FloatingPoint.Type) throws -> FloatingPoint {
    let doubleValue: Double
    if let taggedFloat = taggedValue(for: ConvexTypeKey.float) {
      doubleValue = try decodeDouble(from: taggedFloat)
    } else if let number = value as? NSNumber, !isBool(number) {
      doubleValue = number.doubleValue
    } else {
      throw typeMismatch(type, value: value, codingPath: codingPath)
    }

    return FloatingPoint(doubleValue)
  }

  private func taggedValue(for key: String) -> String? {
    guard let object = value as? [String: Any], object.count == 1 else {
      return nil
    }

    return object[key] as? String
  }

  private func decodeInt64(from base64String: String) throws -> Int64 {
    let data = try decodeBase64Bytes(base64String, expectedByteCount: MemoryLayout<Int64>.size)
    return data.withUnsafeBytes { rawBuffer in
      rawBuffer.loadUnaligned(as: Int64.self)
    }
  }

  private func decodeDouble(from base64String: String) throws -> Double {
    let data = try decodeBase64Bytes(base64String, expectedByteCount: MemoryLayout<Double>.size)
    return data.withUnsafeBytes { rawBuffer in
      rawBuffer.loadUnaligned(as: Double.self)
    }
  }

  private func decodeBase64Bytes(_ base64String: String, expectedByteCount: Int) throws -> Data {
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

private struct ConvexIndexKey: CodingKey {
  let intValue: Int?
  let stringValue: String

  init(index: Int) {
    self.intValue = index
    self.stringValue = "Index \(index)"
  }

  init?(intValue: Int) {
    self.init(index: intValue)
  }

  init?(stringValue: String) {
    self.intValue = nil
    self.stringValue = stringValue
  }
}

private func typeMismatch(_ type: Any.Type, value: Any, codingPath: [CodingKey]) -> DecodingError {
  DecodingError.typeMismatch(
    type,
    DecodingError.Context(
      codingPath: codingPath,
      debugDescription: "Expected \(type), found \(Swift.type(of: value))."
    )
  )
}

private func valueNotFound(_ type: Any.Type, codingPath: [CodingKey]) -> DecodingError {
  DecodingError.valueNotFound(
    type,
    DecodingError.Context(codingPath: codingPath, debugDescription: "Expected \(type), found end of container.")
  )
}

private func isBool(_ number: NSNumber) -> Bool {
  CFGetTypeID(number) == CFBooleanGetTypeID()
}
