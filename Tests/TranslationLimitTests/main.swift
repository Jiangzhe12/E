func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

expect(
    TranslationLimits.maxCharacters == 2_000,
    "translation input limit should be 2000 characters"
)

print("TranslationLimitTests passed")
