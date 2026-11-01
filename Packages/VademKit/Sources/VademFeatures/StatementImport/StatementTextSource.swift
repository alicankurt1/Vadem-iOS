import Foundation

/// A statement file the user picked: the bytes of a PDF or of an image (screenshot, photo, scan).
public enum StatementInput: Sendable, Hashable {
    /// A PDF document's data.
    case pdf(Data)
    /// An image's data in any format ImageIO reads (PNG, JPEG, HEIC, ...).
    case image(Data)
}

/// Why a ``StatementTextSource`` returned no lines.
public enum StatementTextSourceError: Error, Sendable, Equatable {
    /// The file opened but no text was found in it (blank page, photo without text, unreadable scan).
    case nothingReadable
    /// The file could not be opened as the expected kind (damaged, locked PDF, unknown image format).
    case unreadableFile
}

/// Turns a statement file into plain text lines for ``VademCore/StatementParser``.
///
/// Behind a protocol so the import screen and the parser can be tested without real files
/// (see ``ScriptedStatementTextSource``); the app uses ``OnDeviceStatementTextSource``.
public protocol StatementTextSource: Sendable {
    /// The text lines of `input`, top to bottom.
    ///
    /// Throws ``StatementTextSourceError/nothingReadable`` when the file has no text and
    /// ``StatementTextSourceError/unreadableFile`` when it cannot be opened; other errors are failures.
    func lines(from input: StatementInput) async throws -> [String]
}

/// A ``StatementTextSource`` that returns fixed lines (or throws a fixed error) for every input.
///
/// Used by tests and by the debug launch arguments of ``StatementImportView``; it reads no file.
public struct ScriptedStatementTextSource: StatementTextSource {
    private let result: Result<[String], StatementTextSourceError>

    /// Returns `lines` for every input.
    public init(lines: [String]) {
        result = .success(lines)
    }

    /// Throws `error` for every input.
    public init(error: StatementTextSourceError) {
        result = .failure(error)
    }

    public func lines(from input: StatementInput) async throws -> [String] {
        try result.get()
    }
}
