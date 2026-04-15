import Foundation

func assertCondition(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func runChecks() {
    var state = DailyWordTranslationRevealState()

    assertCondition(state.isRevealed(for: "hello") == false, "meaning should be hidden by default")

    state.reveal(for: "hello")
    assertCondition(state.isRevealed(for: "hello"), "meaning should reveal after tapping button")
    assertCondition(state.isRevealed(for: "world") == false, "revealing one word must not reveal another")

    state.resetForWordSwitch()
    assertCondition(state.isRevealed(for: "hello") == false, "switching word should hide translation again")
}

@main
struct DailyWordRevealCheckRunner {
    static func main() {
        runChecks()
        print("daily word reveal checks passed")
    }
}
