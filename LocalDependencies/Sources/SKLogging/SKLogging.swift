//===----------------------------------------------------------------------===//
//
//  This file is a minimal stand-in for the `SKLogging` module that upstream
//  `LanguageServerProtocolTransport` imports. It reproduces only the small API
//  surface the vendored transport modules rely on, with implementations that
//  compile and run with the Workbench's Swift 6.0 toolchain baseline.
//
//  Upstream `SKLogging` (https://github.com/swiftlang/swift-tools-protocols)
//  requires Swift 6.2 and macOS 15. See LocalDependencies/README.md.
//
//===----------------------------------------------------------------------===//

import Foundation
#if canImport(os)
@_exported import os

public typealias LogLevel = OSLogType

/// The default logger used by Grammar Workbench's LSP transport.
///
/// This is computed rather than stored because the open-source `os.Logger`
/// available on Linux is not `Sendable`. A shared global instance would
/// therefore violate Swift 6 strict-concurrency checking.
public var logger: Logger {
  Logger(subsystem: "grammar-workbench-lsp", category: "grammar-workbench")
}
#else
public enum LogLevel: Sendable {
  case `default`
  case info
  case debug
  case error
  case fault
}

/// Source-compatible portable stand-in for the subset of `os.Logger` used by
/// the vendored LSP transport. It intentionally emits nothing: an LSP server
/// must not mix diagnostic logging into its stdout protocol stream.
public struct Logger: Sendable {
  public enum Privacy: Sendable {
    case `public`
    case `private`
  }

  public struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
      public init(literalCapacity: Int, interpolationCount: Int) {}
      public mutating func appendLiteral(_ literal: String) {}
      public mutating func appendInterpolation<T>(_ value: T) {}
      public mutating func appendInterpolation<T>(_ value: T, privacy: Privacy) {}
    }

    public init(stringLiteral value: String) {}
    public init(stringInterpolation: StringInterpolation) {}
  }

  public init(subsystem: String, category: String) {}
  public func log(_ message: Message) {}
  public func log(level: LogLevel, _ message: Message) {}
  public func trace(_ message: Message) {}
  public func debug(_ message: Message) {}
  public func info(_ message: Message) {}
  public func notice(_ message: Message) {}
  public func warning(_ message: Message) {}
  public func error(_ message: Message) {}
  public func critical(_ message: Message) {}
  public func fault(_ message: Message) {}
}

public var logger: Logger {
  Logger(subsystem: "grammar-workbench-lsp", category: "grammar-workbench")
}
#endif

/// Minimal stand-in for the upstream logging-scope configuration point.
public enum LoggingScope {
  public static var subsystem: String { "grammar-workbench-lsp" }
}

/// Like `try?`, but logs the error on failure.
public func orLog<R>(
  _ prefix: @autoclosure () -> String,
  level: LogLevel = .error,
  _ block: () throws -> R?
) -> R? {
  do {
    return try block()
  } catch {
    logError(prefix: prefix(), error: error, level: level)
    return nil
  }
}

/// Like `try?`, but logs the error on failure; supports an `async` body.
public func orLog<R>(
  _ prefix: @autoclosure () -> String,
  level: LogLevel = .error,
  _ block: () async throws -> R?
) async -> R? {
  do {
    return try await block()
  } catch {
    logError(prefix: prefix(), error: error, level: level)
    return nil
  }
}

private func logError(prefix: String, error: Error, level: LogLevel) {
  logger.log(
    level: level,
    "\(prefix, privacy: .public)\(prefix.isEmpty ? "" : ": ", privacy: .public)\(error.forLogging)"
  )
}

/// An object that can be printed for logging and also offers a redacted
/// description for privacy-sensitive contexts.
public protocol CustomLogStringConvertible: CustomStringConvertible, Sendable {
  /// A description of the object that doesn't contain any private information.
  var redactedDescription: String { get }
}

/// An `NSObject` wrapper that OSLog can log in private mode, forwarding to
/// `description` or `redactedDescription` of the wrapped object.
public final class CustomLogStringConvertibleWrapper: NSObject, Sendable {
  private let underlyingObject: any CustomLogStringConvertible

  fileprivate init(_ underlyingObject: any CustomLogStringConvertible) {
    self.underlyingObject = underlyingObject
  }

  public override var description: String {
    underlyingObject.description
  }

#if canImport(ObjectiveC)
  @objc
#endif
  public var redactedDescription: String {
    underlyingObject.redactedDescription
  }
}

extension CustomLogStringConvertible {
  /// An object that logs the full `description` normally and the
  /// `redactedDescription` when private information is disabled.
  public var forLogging: CustomLogStringConvertibleWrapper {
    CustomLogStringConvertibleWrapper(self)
  }
}

extension String {
  /// A redacted stand-in for logging.
  public var hashForLogging: String { "<private>" }
}

extension Encodable {
  /// Pretty-printed JSON, used for logging.
  public var prettyPrintedJSON: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else {
      return "\(self)"
    }
    return string.replacingOccurrences(of: "\\/", with: "/")
  }

  /// Pretty-printed JSON with string values redacted.
  public var prettyPrintedRedactedJSON: String {
    func redact(subject: Any) -> Any {
      if let dictionary = subject as? [String: Any] {
        return dictionary.mapValues { redact(subject: $0) }
      } else if let array = subject as? [Any] {
        return array.map { redact(subject: $0) }
      } else if subject is String {
        return "<private>"
      } else {
        return subject
      }
    }

    guard
      let encoded = try? JSONEncoder().encode(self),
      let jsonObject = try? JSONSerialization.jsonObject(with: encoded),
      let data = try? JSONSerialization.data(
        withJSONObject: redact(subject: jsonObject),
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      ),
      let string = String(data: data, encoding: .utf8)
    else {
      return "<private>"
    }
    return string
  }
}

extension Error {
  /// A version of the error that can be used for logging without leaking
  /// sensitive wording into private log output.
  public var forLogging: CustomLogStringConvertibleWrapper {
    if let error = self as? CustomLogStringConvertible {
      return error.forLogging
    }
    return MaskedError(self).forLogging
  }
}

private struct MaskedError: CustomLogStringConvertible {
  let underlyingError: any Error

  init(_ underlyingError: any Error) {
    self.underlyingError = underlyingError
  }

  var description: String {
    "\(underlyingError)"
  }

  var redactedDescription: String {
    let error = underlyingError as NSError
    return "\(error.code): \(String(describing: error).hashForLogging)"
  }
}
