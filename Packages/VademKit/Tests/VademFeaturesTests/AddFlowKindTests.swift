import Foundation
import Testing
import VademCore
import VademFeatures

@Suite("AddFlowKind and gallery helpers")
struct AddFlowKindTests {
    @Test("Sheet offers Installment, Subscription, Payment in that order")
    func order() {
        #expect(AddFlowKind.allCases == [.installment, .subscription, .payment])
    }

    @Test("Identifiers are add.sheet.<kind>", arguments: [
        (AddFlowKind.installment, "add.sheet.installment"),
        (AddFlowKind.subscription, "add.sheet.subscription"),
        (AddFlowKind.payment, "add.sheet.payment"),
    ])
    func identifiers(kind: AddFlowKind, expected: String) {
        #expect(kind.accessibilityIdentifier == expected)
        #expect(kind.id == kind.rawValue)
    }

    @Test("Only subscription opens an existing form; installment and payment run inside the sheet", arguments: [
        (AddFlowKind.installment, false),
        (AddFlowKind.subscription, true),
        (AddFlowKind.payment, false),
    ])
    func opensExistingForm(kind: AddFlowKind, expected: Bool) {
        #expect(kind.opensExistingForm == expected)
    }

    @Test("Every kind has a title, subtitle and symbol; kinds are told apart", arguments: AddFlowKind.allCases)
    func texts(kind: AddFlowKind) {
        #expect(!kind.title.isEmpty)
        #expect(!kind.subtitle.isEmpty)
        #expect(!kind.systemImage.isEmpty)
        #expect(Set(AddFlowKind.allCases.map(\.title)).count == 3)
        #expect(Set(AddFlowKind.allCases.map(\.systemImage)).count == 3)
    }

    @Test("Gallery launch arguments are the documented ones", arguments: [
        (AddFlowGalleryStep.keypad, "-ui-add-flow-keypad"),
        (AddFlowGalleryStep.chips, "-ui-add-flow-chips"),
        (AddFlowGalleryStep.cardPicker, "-ui-add-flow-card"),
    ])
    func galleryArguments(step: AddFlowGalleryStep, expected: String) {
        #expect(step.launchArgument == expected)
        #expect(AddFlowGalleryStep.step(in: ["-ui-static-motion", expected]) == step)
    }

    @Test("Installment flow launch argument")
    func installmentFlowArgument() {
        #expect(InstallmentFlowView.launchArgument == "-ui-add-installment-flow")
    }

    @Test("Sheet launch argument")
    func sheetArgument() {
        #expect(AddFlowSheet.launchArgument == "-ui-add-sheet")
    }

    @Test("No gallery argument gives no step; several give the first in step order")
    func galleryLookup() {
        #expect(AddFlowGalleryStep.step(in: []) == nil)
        #expect(AddFlowGalleryStep.step(in: ["-ui-sample-data", "-ui-add-sheet"]) == nil)
        #expect(AddFlowGalleryStep.step(in: ["-ui-add-flow-card", "-ui-add-flow-chips"]) == .chips)
    }

    @Test("Gallery steps are keypad, chips, card picker in order")
    func galleryOrder() {
        #expect(AddFlowGalleryStep.allCases == [.keypad, .chips, .cardPicker])
    }
}

@Suite("CardPicker.initialSelection")
struct CardPickerTests {
    private let first = Card(name: "Bonus", statementDay: 5, dueDay: 15)!
    private let second = Card(name: "World", statementDay: 10, dueDay: 20)!

    @Test("Last used card is preselected when it still exists")
    func lastUsed() {
        #expect(CardPicker.initialSelection(cards: [first, second], lastUsedCardID: second.id) == second.id)
        #expect(CardPicker.initialSelection(cards: [first, second], lastUsedCardID: first.id) == first.id)
    }

    @Test("No last used card selects No card")
    func noneUsed() {
        #expect(CardPicker.initialSelection(cards: [first, second], lastUsedCardID: nil) == nil)
    }

    @Test("A deleted last used card selects No card")
    func deleted() {
        #expect(CardPicker.initialSelection(cards: [first], lastUsedCardID: second.id) == nil)
    }

    @Test("Empty card list selects No card")
    func empty() {
        #expect(CardPicker.initialSelection(cards: [], lastUsedCardID: first.id) == nil)
    }
}
