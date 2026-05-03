import Foundation

public typealias ConvexValue = any Sendable

public enum ConvexEncodingError: Error, Equatable {
  case unsupportedValue(String)
  case invalidJSON(String)
}

/// Encodes Swift values into Convex's JSON argument format.
public struct ConvexEncoder: Sendable {
  public init() {}

  /// Encodes a Swift value into the JSON string expected by the Convex transport.
  public func encode(_ value: ConvexValue?) throws -> String {
    try ConvexArgumentEncoder.string(from: ConvexArgumentEncoder.jsonObject(from: value))
  }
}

enum ConvexArgumentEncoder {
  static func encode(_ args: [String: ConvexValue?]?) throws -> [String: String] {
    guard let args else {
      return [:]
    }

    var encodedArgs = [String: String]()
    encodedArgs.reserveCapacity(args.count)

    for (key, value) in args {
      encodedArgs[key] = try ConvexEncoder().encode(value)
    }

    return encodedArgs
  }

  static func jsonObject(from value: ConvexValue?) throws -> Any {
    guard let value else {
      return NSNull()
    }

    switch value {
    case let value as Int:
      return integerObject(Int64(value))
    case let value as Int32:
      return integerObject(Int64(value))
    case let value as Int64:
      return integerObject(value)
    case let value as Float:
      return floatObject(value)
    case let value as Double:
      return floatObject(value)
    case let value as Bool:
      return value
    case let value as String:
      return value
    case let value as [String: ConvexValue?]:
      var object = [String: Any]()
      for key in value.keys.sorted() {
        object[key] = try jsonObject(from: value[key] ?? nil)
      }
      return object
    case let value as [ConvexValue?]:
      return try value.map { try jsonObject(from: $0) }
    default:
      throw ConvexEncodingError.unsupportedValue(String(describing: type(of: value)))
    }
  }

  static func string(from jsonObject: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.fragmentsAllowed, .sortedKeys])
    return String(decoding: data, as: UTF8.self)
  }

  private static func integerObject(_ value: Int64) -> [String: String] {
    let data = withUnsafeBytes(of: value) { Data($0) }
    return ["$integer": data.base64EncodedString()]
  }

  private static func floatObject(_ value: Float) -> Any {
    floatObject(Double(value))
  }

  private static func floatObject(_ value: Double) -> Any {
    guard value.isNaN || value == Double.infinity || value == -Double.infinity else {
      return value
    }

    let data = withUnsafeBytes(of: value) { Data($0) }
    return ["$float": data.base64EncodedString()]
  }
}
