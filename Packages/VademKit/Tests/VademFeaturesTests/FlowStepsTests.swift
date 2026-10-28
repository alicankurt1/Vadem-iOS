import Testing
import VademFeatures

@Suite("FlowSteps")
struct FlowStepsTests {
    @Test("Starts on the first step")
    func start() {
        let flow = FlowSteps(["a", "b", "c"])
        #expect(flow.current == "a")
        #expect(flow.number == 1)
        #expect(flow.count == 3)
        #expect(flow.isFirst)
        #expect(!flow.isLast)
    }

    @Test("Starts at a given step", arguments: [("a", 1), ("b", 2), ("c", 3)])
    func startingAt(step: String, number: Int) {
        let flow = FlowSteps(["a", "b", "c"], startingAt: step)
        #expect(flow.current == step)
        #expect(flow.number == number)
    }

    @Test("Unknown start falls back to the first step")
    func unknownStart() {
        let flow = FlowSteps(["a", "b"], startingAt: "z")
        #expect(flow.current == "a")
        #expect(flow.isFirst)
    }

    @Test("Advance moves forward and stops on the last step")
    func advance() {
        var flow = FlowSteps(["a", "b", "c"])
        let movedAdvance982 = flow.advance()
        #expect(movedAdvance982)
        #expect(flow.current == "b")
        let movedAdvance51 = flow.advance()
        #expect(movedAdvance51)
        #expect(flow.current == "c")
        #expect(flow.isLast)
        let movedAdvance149 = flow.advance()
        #expect(!movedAdvance149)
        #expect(flow.current == "c")
        #expect(flow.number == 3)
    }

    @Test("Go back moves backward and stops on the first step")
    func goBack() {
        var flow = FlowSteps(["a", "b", "c"], startingAt: "c")
        let movedGoback407 = flow.goBack()
        #expect(movedGoback407)
        #expect(flow.current == "b")
        let movedGoback475 = flow.goBack()
        #expect(movedGoback475)
        #expect(flow.current == "a")
        let movedGoback543 = flow.goBack()
        #expect(!movedGoback543)
        #expect(flow.current == "a")
    }

    @Test("A single-step flow is first and last and cannot move")
    func singleStep() {
        var flow = FlowSteps(["only"])
        #expect(flow.isFirst && flow.isLast)
        let movedAdvance793 = flow.advance()
        #expect(!movedAdvance793)
        let movedGoback826 = flow.goBack()
        #expect(!movedGoback826)
        #expect(flow.number == 1)
        #expect(flow.count == 1)
    }

    @Test("Advance then go back returns to the same state")
    func roundTrip() {
        var flow = FlowSteps([1, 2, 3])
        let before = flow
        flow.advance()
        flow.goBack()
        #expect(flow == before)
    }
}
