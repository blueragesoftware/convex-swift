import Foundation

public enum ConvexEncodingError: Error, Equatable {
  case invalidTopLevelArguments(String)
  case invalidJSON(String)
}

/// Encodes Swift `Encodable` values into Convex's JSON argument format.
///
/// Integer values are encoded into Convex's tagged `$integer` representation. Finite floating-point values
/// are encoded as JSON numbers, while `NaN` and infinities are encoded into Convex's tagged `$float`
/// representation.
public struct ConvexEncoder: Sendable {
  public init() {}

  /// Encodes an `Encodable` value into a JSON string that can be sent to Convex.
  public func encode<Value: Encodable>(_ value: Value) throws -> String {
    try ConvexJSONWriter.string(from: ConvexEncoding.encode(value))
  }
}

enum ConvexArgumentEncoder {
  static func encode<Args: Encodable>(_ args: Args?) throws -> [String: String] {
    guard let args else {
      return [:]
    }

    let encoded = try ConvexEncoding.encode(args)
    guard let object = encoded as? [String: Any] else {
      throw ConvexEncodingError.invalidTopLevelArguments(String(describing: Args.self))
    }

    var encodedArgs = [String: String]()
    encodedArgs.reserveCapacity(object.count)

    for key in object.keys.sorted() {
      encodedArgs[key] = try ConvexJSONWriter.string(from: object[key] ?? NSNull())
    }

    return encodedArgs
  }
}

private enum ConvexEncoding {
  static func encode<Value: Encodable>(_ value: Value, codingPath: [CodingKey] = []) throws -> Any {
    let box = ConvexEncodingBox()
    let encoder = ConvexValueEncoder(box: box, codingPath: codingPath)
    try value.encode(to: encoder)
    return box.value ?? NSNull()
  }
}

private final class ConvexEncodingBox {
  var value: Any? {
    didSet {
      onUpdate(value)
    }
  }

  private let onUpdate: (Any?) -> Void

  init(onUpdate: @escaping (Any?) -> Void = { _ in }) {
    self.onUpdate = onUpdate
  }
}

private struct ConvexValueEncoder: Encoder {
  let box: ConvexEncodingBox
  let codingPath: [CodingKey]
  var userInfo: [CodingUserInfoKey: Any] { [:] }

  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    if box.value == nil {
      box.value = [String: Any]()
    }

    return KeyedEncodingContainer(ConvexKeyedEncodingContainer<Key>(box: box, codingPath: codingPath))
  }

  func unkeyedContainer() -> UnkeyedEncodingContainer {
    if box.value == nil {
      box.value = [Any]()
    }

    return ConvexUnkeyedEncodingContainer(box: box, codingPath: codingPath)
  }

  func singleValueContainer() -> SingleValueEncodingContainer {
    ConvexSingleValueEncodingContainer(box: box, codingPath: codingPath)
  }
}

private struct ConvexKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let box: ConvexEncodingBox
  let codingPath: [CodingKey]

  mutating func encodeNil(forKey key: Key) throws {
    try set(NSNull(), forKey: key)
  }

  mutating func encode(_ value: Bool, forKey key: Key) throws {
    try set(value, forKey: key)
  }

  mutating func encode(_ value: String, forKey key: Key) throws {
    try set(value, forKey: key)
  }

  mutating func encode(_ value: Double, forKey key: Key) throws {
    try set(ConvexNumberEncoding.floatObject(value), forKey: key)
  }

  mutating func encode(_ value: Float, forKey key: Key) throws {
    try set(ConvexNumberEncoding.floatObject(value), forKey: key)
  }

  mutating func encode(_ value: Int, forKey key: Key) throws {
    try set(ConvexNumberEncoding.integerObject(Int64(value)), forKey: key)
  }

  mutating func encode(_ value: Int8, forKey key: Key) throws {
    try set(ConvexNumberEncoding.integerObject(Int64(value)), forKey: key)
  }

  mutating func encode(_ value: Int16, forKey key: Key) throws {
    try set(ConvexNumberEncoding.integerObject(Int64(value)), forKey: key)
  }

  mutating func encode(_ value: Int32, forKey key: Key) throws {
    try set(ConvexNumberEncoding.integerObject(Int64(value)), forKey: key)
  }

  mutating func encode(_ value: Int64, forKey key: Key) throws {
    try set(ConvexNumberEncoding.integerObject(value), forKey: key)
  }

  mutating func encode(_ value: UInt, forKey key: Key) throws {
    try set(ConvexNumberEncoding.unsignedIntegerObject(value), forKey: key)
  }

  mutating func encode(_ value: UInt8, forKey key: Key) throws {
    try set(ConvexNumberEncoding.integerObject(Int64(value)), forKey: key)
  }

  mutating func encode(_ value: UInt16, forKey key: Key) throws {
    try set(ConvexNumberEncoding.integerObject(Int64(value)), forKey: key)
  }

  mutating func encode(_ value: UInt32, forKey key: Key) throws {
    try set(ConvexNumberEncoding.integerObject(Int64(value)), forKey: key)
  }

  mutating func encode(_ value: UInt64, forKey key: Key) throws {
    try set(ConvexNumberEncoding.unsignedIntegerObject(value), forKey: key)
  }

  mutating func encode<Value: Encodable>(_ value: Value, forKey key: Key) throws {
    try set(ConvexEncoding.encode(value, codingPath: codingPath + [key]), forKey: key)
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type,
    forKey key: Key
  ) -> KeyedEncodingContainer<NestedKey> {
    let childBox = ConvexEncodingBox { [box] value in
      var object = box.value as? [String: Any] ?? [:]
      object[key.stringValue] = value ?? NSNull()
      box.value = object
    }
    childBox.value = [String: Any]()
    return KeyedEncodingContainer(ConvexKeyedEncodingContainer<NestedKey>(box: childBox, codingPath: codingPath + [key]))
  }

  mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
    let childBox = ConvexEncodingBox { [box] value in
      var object = box.value as? [String: Any] ?? [:]
      object[key.stringValue] = value ?? NSNull()
      box.value = object
    }
    childBox.value = [Any]()
    return ConvexUnkeyedEncodingContainer(box: childBox, codingPath: codingPath + [key])
  }

  mutating func superEncoder() -> Encoder {
    ConvexValueEncoder(box: box, codingPath: codingPath)
  }

  mutating func superEncoder(forKey key: Key) -> Encoder {
    ConvexValueEncoder(box: box, codingPath: codingPath + [key])
  }

  private func set(_ value: Any, forKey key: Key) throws {
    guard var object = box.value as? [String: Any] else {
      throw ConvexEncodingError.invalidTopLevelArguments("Expected keyed container at \(codingPath).")
    }

    object[key.stringValue] = value
    box.value = object
  }

}

private struct ConvexUnkeyedEncodingContainer: UnkeyedEncodingContainer {
  let box: ConvexEncodingBox
  let codingPath: [CodingKey]
  var count: Int { (box.value as? [Any])?.count ?? 0 }

  mutating func encodeNil() throws {
    try append(NSNull())
  }

  mutating func encode(_ value: Bool) throws { try append(value) }
  mutating func encode(_ value: String) throws { try append(value) }
  mutating func encode(_ value: Double) throws { try append(ConvexNumberEncoding.floatObject(value)) }
  mutating func encode(_ value: Float) throws { try append(ConvexNumberEncoding.floatObject(value)) }
  mutating func encode(_ value: Int) throws { try append(ConvexNumberEncoding.integerObject(Int64(value))) }
  mutating func encode(_ value: Int8) throws { try append(ConvexNumberEncoding.integerObject(Int64(value))) }
  mutating func encode(_ value: Int16) throws { try append(ConvexNumberEncoding.integerObject(Int64(value))) }
  mutating func encode(_ value: Int32) throws { try append(ConvexNumberEncoding.integerObject(Int64(value))) }
  mutating func encode(_ value: Int64) throws { try append(ConvexNumberEncoding.integerObject(value)) }
  mutating func encode(_ value: UInt) throws { try append(ConvexNumberEncoding.unsignedIntegerObject(value)) }
  mutating func encode(_ value: UInt8) throws { try append(ConvexNumberEncoding.integerObject(Int64(value))) }
  mutating func encode(_ value: UInt16) throws { try append(ConvexNumberEncoding.integerObject(Int64(value))) }
  mutating func encode(_ value: UInt32) throws { try append(ConvexNumberEncoding.integerObject(Int64(value))) }
  mutating func encode(_ value: UInt64) throws { try append(ConvexNumberEncoding.unsignedIntegerObject(value)) }

  mutating func encode<Value: Encodable>(_ value: Value) throws {
    try append(ConvexEncoding.encode(value, codingPath: codingPath + [ConvexIndexKey(index: count)]))
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type
  ) -> KeyedEncodingContainer<NestedKey> {
    let index = count
    appendUnchecked([String: Any]())
    let childBox = ConvexEncodingBox { [box] value in
      var array = box.value as? [Any] ?? []
      guard array.indices.contains(index) else {
        return
      }
      array[index] = value ?? NSNull()
      box.value = array
    }
    childBox.value = [String: Any]()
    return KeyedEncodingContainer(ConvexKeyedEncodingContainer<NestedKey>(box: childBox, codingPath: codingPath + [ConvexIndexKey(index: index)]))
  }

  mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
    let index = count
    appendUnchecked([Any]())
    let childBox = ConvexEncodingBox { [box] value in
      var array = box.value as? [Any] ?? []
      guard array.indices.contains(index) else {
        return
      }
      array[index] = value ?? NSNull()
      box.value = array
    }
    childBox.value = [Any]()
    return ConvexUnkeyedEncodingContainer(box: childBox, codingPath: codingPath + [ConvexIndexKey(index: index)])
  }

  mutating func superEncoder() -> Encoder {
    ConvexValueEncoder(box: box, codingPath: codingPath)
  }

  private func append(_ value: Any) throws {
    guard var array = box.value as? [Any] else {
      throw ConvexEncodingError.invalidTopLevelArguments("Expected unkeyed container at \(codingPath).")
    }

    array.append(value)
    box.value = array
  }

  private func appendUnchecked(_ value: Any) {
    var array = box.value as? [Any] ?? []
    array.append(value)
    box.value = array
  }
}

private struct ConvexSingleValueEncodingContainer: SingleValueEncodingContainer {
  let box: ConvexEncodingBox
  let codingPath: [CodingKey]

  mutating func encodeNil() throws { box.value = NSNull() }
  mutating func encode(_ value: Bool) throws { box.value = value }
  mutating func encode(_ value: String) throws { box.value = value }
  mutating func encode(_ value: Double) throws { box.value = ConvexNumberEncoding.floatObject(value) }
  mutating func encode(_ value: Float) throws { box.value = ConvexNumberEncoding.floatObject(value) }
  mutating func encode(_ value: Int) throws { box.value = ConvexNumberEncoding.integerObject(Int64(value)) }
  mutating func encode(_ value: Int8) throws { box.value = ConvexNumberEncoding.integerObject(Int64(value)) }
  mutating func encode(_ value: Int16) throws { box.value = ConvexNumberEncoding.integerObject(Int64(value)) }
  mutating func encode(_ value: Int32) throws { box.value = ConvexNumberEncoding.integerObject(Int64(value)) }
  mutating func encode(_ value: Int64) throws { box.value = ConvexNumberEncoding.integerObject(value) }
  mutating func encode(_ value: UInt) throws { box.value = try ConvexNumberEncoding.unsignedIntegerObject(value) }
  mutating func encode(_ value: UInt8) throws { box.value = ConvexNumberEncoding.integerObject(Int64(value)) }
  mutating func encode(_ value: UInt16) throws { box.value = ConvexNumberEncoding.integerObject(Int64(value)) }
  mutating func encode(_ value: UInt32) throws { box.value = ConvexNumberEncoding.integerObject(Int64(value)) }
  mutating func encode(_ value: UInt64) throws { box.value = try ConvexNumberEncoding.unsignedIntegerObject(value) }

  mutating func encode<Value: Encodable>(_ value: Value) throws {
    box.value = try ConvexEncoding.encode(value, codingPath: codingPath)
  }
}

private enum ConvexNumberEncoding {
  static func integerObject(_ value: Int64) -> [String: String] {
    let data = withUnsafeBytes(of: value) { Data($0) }
    return ["$integer": data.base64EncodedString()]
  }

  static func unsignedIntegerObject(_ value: UInt) throws -> [String: String] {
    guard let signedValue = Int64(exactly: value) else {
      throw ConvexEncodingError.invalidJSON("\(value) cannot be represented as Int64.")
    }
    return integerObject(signedValue)
  }

  static func unsignedIntegerObject(_ value: UInt64) throws -> [String: String] {
    guard let signedValue = Int64(exactly: value) else {
      throw ConvexEncodingError.invalidJSON("\(value) cannot be represented as Int64.")
    }
    return integerObject(signedValue)
  }

  static func floatObject(_ value: Float) -> Any {
    floatObject(Double(value))
  }

  static func floatObject(_ value: Double) -> Any {
    guard value.isNaN || value == Double.infinity || value == -Double.infinity else {
      return value
    }

    let data = withUnsafeBytes(of: value) { Data($0) }
    return ["$float": data.base64EncodedString()]
  }
}

private enum ConvexJSONWriter {
  static func string(from jsonObject: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.fragmentsAllowed, .sortedKeys])
    return String(decoding: data, as: UTF8.self)
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
