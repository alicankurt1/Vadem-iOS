import CoreGraphics
import Foundation
import Testing
import VademCore

@testable import VademFeatures

// Sahte metin kaynağıyla ekstre içe aktarma modeli; dosya okunmaz.
@MainActor
@Suite("StatementImportViewModel")
struct StatementImportViewModelTests {
    private static let installmentLines = [
        "12.10.2026 ORNEK ELEKTRONIK 3/6 1.234,56 TL",
        "ORNEK MARKET 85,50",
        "15.10.2026 ORNEK GIYIM Taksit 2/4 450,00",
    ]

    /// Okumayı bekleyen, elle serbest bırakılan kaynak ("okunuyor" durumunu gözlemlemek için).
    actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }

    struct GatedSource: StatementTextSource {
        let gate: Gate
        let lines: [String]
        func lines(from input: StatementInput) async throws -> [String] {
            await gate.wait()
            return lines
        }
    }

    struct FailingSource: StatementTextSource {
        struct Boom: Error {}
        func lines(from input: StatementInput) async throws -> [String] { throw Boom() }
    }

    @Test("Starts idle")
    func startsIdle() {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: []))
        #expect(model.state == .idle)
        #expect(!model.isReading)
    }

    @Test("Installment lines end in found, in statement order")
    func found() async throws {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: Self.installmentLines))
        await model.read(.pdf(Data()))
        guard case .found(let candidates) = model.state else {
            Issue.record("expected found, got \(model.state)")
            return
        }
        #expect(candidates.count == 2)
        #expect(candidates.map(\.currentInstallment) == [3, 2])
        #expect(candidates.map(\.totalInstallments) == [6, 4])
        #expect(candidates.map(\.installmentAmount) == [Decimal(string: "1234.56")!, 450])
    }

    @Test("Reading state shows while the source works, then resolves")
    func readingState() async {
        let gate = Gate()
        let model = StatementImportViewModel(source: GatedSource(gate: gate, lines: Self.installmentLines))
        let task = Task { await model.read(.image(Data())) }
        while model.state != .reading { await Task.yield() }
        #expect(model.isReading)
        await gate.open()
        await task.value
        #expect(!model.isReading)
        if case .found = model.state {} else { Issue.record("expected found, got \(model.state)") }
    }

    @Test("A second read while reading is ignored")
    func ignoresReadWhileReading() async {
        let gate = Gate()
        let model = StatementImportViewModel(source: GatedSource(gate: gate, lines: Self.installmentLines))
        var handedOff = 0
        model.onCandidatesFound = { _ in handedOff += 1 }
        let task = Task { await model.read(.pdf(Data())) }
        while model.state != .reading { await Task.yield() }
        await model.read(.pdf(Data()))
        #expect(model.state == .reading)
        await gate.open()
        await task.value
        #expect(handedOff == 1)
    }

    @Test("Source reporting nothingReadable gives noText")
    func noTextFromSource() async {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(error: .nothingReadable))
        await model.read(.image(Data()))
        #expect(model.state == .noText)
    }

    @Test("Empty or blank lines give noText", arguments: [[], [""], ["   ", "\t"]] as [[String]])
    func blankLines(lines: [String]) async {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: lines))
        await model.read(.pdf(Data()))
        #expect(model.state == .noText)
    }

    @Test("Text without installment markers gives noInstallments")
    func noInstallments() async {
        let model = StatementImportViewModel(
            source: ScriptedStatementTextSource(lines: ["ORNEK MARKET 85,50", "DONEM BORCU TOPLAMI 85,50"])
        )
        await model.read(.pdf(Data()))
        #expect(model.state == .noInstallments)
    }

    @Test("Unreadable file and other errors give failed")
    func failures() async {
        let unreadable = StatementImportViewModel(source: ScriptedStatementTextSource(error: .unreadableFile))
        await unreadable.read(.pdf(Data()))
        #expect(unreadable.state == .failed)

        let other = StatementImportViewModel(source: FailingSource())
        await other.read(.pdf(Data()))
        #expect(other.state == .failed)
    }

    @Test("Image loader returning nil or throwing gives failed")
    func imageLoadFailures() async {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: Self.installmentLines))
        await model.readImage { nil }
        #expect(model.state == .failed)
        await model.readImage { throw FailingSource.Boom() }
        #expect(model.state == .failed)
        await model.readImage { Data([1]) }
        if case .found = model.state {} else { Issue.record("expected found after a good image, got \(model.state)") }
    }

    @Test("A missing PDF file gives failed")
    func missingPDF() async {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: Self.installmentLines))
        await model.readPDF(at: URL(fileURLWithPath: "/nonexistent/statement.pdf"))
        #expect(model.state == .failed)
    }

    @Test("showFailure sets failed")
    func showFailure() {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: []))
        model.showFailure()
        #expect(model.state == .failed)
    }

    @Test("Hand-off: candidates go to onCandidatesFound once, only when found")
    func handOff() async {
        var received: [[InstallmentCandidate]] = []
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: Self.installmentLines))
        model.onCandidatesFound = { received.append($0) }
        await model.read(.pdf(Data()))
        #expect(received.count == 1)
        if case .found(let candidates) = model.state { #expect(received.first == candidates) }

        // Bulunamayan durumlarda devredilmez.
        let empty = StatementImportViewModel(source: ScriptedStatementTextSource(lines: ["ORNEK MARKET 85,50"]))
        var emptyCalls = 0
        empty.onCandidatesFound = { _ in emptyCalls += 1 }
        await empty.read(.pdf(Data()))
        let blank = StatementImportViewModel(source: ScriptedStatementTextSource(error: .nothingReadable))
        blank.onCandidatesFound = { _ in emptyCalls += 1 }
        await blank.read(.pdf(Data()))
        #expect(emptyCalls == 0)
    }

    @Test("A new read after a result replaces the state")
    func rereadReplacesState() async {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: ["ORNEK MARKET 85,50"]))
        await model.read(.pdf(Data()))
        #expect(model.state == .noInstallments)
        model.show(lines: Self.installmentLines)
        if case .found = model.state {} else { Issue.record("expected found") }
    }

    @Test("Launch states: every state has a distinct argument and builds a matching model")
    func launchStates() {
        let args = StatementImportLaunchState.allCases.map(\.launchArgument)
        #expect(Set(args).count == args.count)
        #expect(StatementImportLaunchState.found.makeModel().state != .idle)
        #expect(StatementImportLaunchState.noText.makeModel().state == .noText)
        #expect(StatementImportLaunchState.noInstallments.makeModel().state == .noInstallments)
        #expect(StatementImportLaunchState.failed.makeModel().state == .failed)
        #expect(StatementImportLaunchState.idle.makeModel().state == .idle)
        #expect(StatementImportLaunchState.state(in: ["-ui-statement-import-no-text"]) == .noText)
        #expect(StatementImportLaunchState.state(in: ["-ui-other"]) == nil)
    }
}

@Suite("StatementLineAssembler")
struct StatementLineAssemblerTests {
    private func box(_ text: String, x: Double, y: Double, h: Double = 0.04) -> RecognizedTextBox {
        RecognizedTextBox(text: text, boundingBox: CGRect(x: x, y: y, width: 0.2, height: h))
    }

    @Test("Rows come top to bottom (Vision y grows upward)")
    func topToBottom() {
        let lines = StatementLineAssembler.lines(from: [
            box("bottom", x: 0.1, y: 0.1),
            box("top", x: 0.1, y: 0.9),
            box("middle", x: 0.1, y: 0.5),
        ])
        #expect(lines == ["top", "middle", "bottom"])
    }

    @Test("Boxes on one row are joined left to right")
    func joinsRow() {
        let lines = StatementLineAssembler.lines(from: [
            box("1.234,56", x: 0.7, y: 0.50),
            box("ORNEK 3/6", x: 0.3, y: 0.505),
            box("12.10.2026", x: 0.05, y: 0.498),
            box("NEXT", x: 0.05, y: 0.30),
        ])
        #expect(lines == ["12.10.2026 ORNEK 3/6 1.234,56", "NEXT"])
    }

    @Test("Rows further apart than half a row height stay separate")
    func separateRows() {
        let lines = StatementLineAssembler.lines(from: [
            box("A", x: 0.1, y: 0.50), box("B", x: 0.5, y: 0.45),
        ])
        #expect(lines == ["A", "B"])
    }

    @Test("Empty and whitespace boxes are dropped, texts trimmed")
    func dropsEmpty() {
        let lines = StatementLineAssembler.lines(from: [
            box("  ", x: 0.1, y: 0.9), box("", x: 0.1, y: 0.7), box(" KEEP \n", x: 0.1, y: 0.5),
        ])
        #expect(lines == ["KEEP"])
    }

    @Test("No boxes give no lines")
    func empty() {
        #expect(StatementLineAssembler.lines(from: []).isEmpty)
    }

    @Test("Assembled OCR pieces parse into an installment")
    func feedsParser() {
        let lines = StatementLineAssembler.lines(from: [
            box("1.234,56 TL", x: 0.7, y: 0.5), box("ORNEK ELEKTRONIK", x: 0.2, y: 0.5), box("3/6", x: 0.5, y: 0.5),
        ])
        let candidates = StatementParser.parse(lines: lines)
        #expect(candidates.count == 1)
        #expect(candidates.first?.currentInstallment == 3)
        #expect(candidates.first?.totalInstallments == 6)
        #expect(candidates.first?.installmentAmount == Decimal(string: "1234.56"))
    }
}
