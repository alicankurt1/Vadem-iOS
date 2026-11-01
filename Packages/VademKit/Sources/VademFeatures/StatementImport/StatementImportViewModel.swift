import Foundation
import Observation
import VademCore

/// Reads a statement file through a ``StatementTextSource`` and finds its installments and statement total
/// with ``VademCore/StatementParser``.
///
/// ``state`` goes `idle → reading → found / noText / noInstallments / failed`; a new file can be read from any
/// state except `reading`. A statement with a total and due date but no installment line is still found (with
/// no candidates), so its total can be reviewed. Found candidates are also handed to ``onCandidatesFound``.
@MainActor
@Observable
public final class StatementImportViewModel: Identifiable {
    /// Where the import is.
    public enum State: Equatable, Sendable {
        /// Nothing picked yet.
        case idle
        /// A file is being read.
        case reading
        /// Installment lines (in statement order) or a statement summary were found; `candidates` may be empty
        /// only when `summary` is not `nil`.
        case found([InstallmentCandidate], summary: StatementSummary?)
        /// The file had no readable text.
        case noText
        /// The file had text but no installment line and no statement summary.
        case noInstallments
        /// The file could not be opened or read.
        case failed
    }

    /// The current state.
    public private(set) var state: State = .idle

    /// Called with the candidates whenever a read ends in ``State/found(_:summary:)``.
    public var onCandidatesFound: (([InstallmentCandidate]) -> Void)?

    private let source: any StatementTextSource

    /// Creates the model; `source` turns picked files into text lines.
    public init(source: any StatementTextSource) {
        self.source = source
    }

    /// `true` while a file is being read; the pick buttons are disabled then.
    public var isReading: Bool { state == .reading }

    /// Reads `input` and updates ``state``; ignored while another read is running.
    public func read(_ input: StatementInput) async {
        await run { input }
    }

    /// Reads the PDF at `url` (from the document picker, so security-scoped) and updates ``state``.
    public func readPDF(at url: URL) async {
        await run {
            // Dosya uygulamanın kabının dışında: erişim yalnızca okuma süresince açık tutulur.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
            return .pdf(data)
        }
    }

    /// Reads the image `load` returns (e.g. the photo picker's data) and updates ``state``;
    /// `nil` or a thrown error means the image could not be loaded (``State/failed``).
    public func readImage(loading load: () async throws -> Data?) async {
        await run {
            guard let data = try await load() else { throw StatementTextSourceError.unreadableFile }
            return .image(data)
        }
    }

    // Ortak akış: okuma sürerken yeni okuma yok; dosya yükleme de "okunuyor" durumunda geçer.
    private func run(_ load: () async throws -> StatementInput) async {
        guard !isReading else { return }
        state = .reading
        do {
            let input = try await load()
            let lines = try await source.lines(from: input)
            show(lines: lines)
        } catch StatementTextSourceError.nothingReadable {
            state = .noText
        } catch {
            state = .failed
        }
    }

    /// Shows that a picked file could not be opened (e.g. the document picker reported an error).
    public func showFailure() {
        state = .failed
    }

    /// Turns text lines into a result: parses them and sets ``state`` (no lines means no text, neither
    /// installments nor a summary means no installments).
    public func show(lines: [String]) {
        guard lines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            state = .noText
            return
        }
        let result = StatementParser.parseStatement(lines: lines)
        if result.candidates.isEmpty, result.summary == nil {
            state = .noInstallments
        } else {
            state = .found(result.candidates, summary: result.summary)
            onCandidatesFound?(result.candidates)
        }
    }
}
