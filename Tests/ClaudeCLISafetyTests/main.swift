import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

let promptURL = URL(fileURLWithPath: "/tmp/ec-test-prompt.txt")
let command = ClaudeCLITranslationProvider.makeCommand(
    model: "claude-sonnet-4-6",
    promptURL: promptURL
)

expect(command.contains("--safe-mode"), "CLI translation should disable Claude Code customizations")
expect(command.contains("--no-session-persistence"), "CLI translation should not persist sessions")
expect(command.contains("--permission-mode dontAsk"), "CLI translation should not ask for file/tool permissions")
expect(command.contains("--tools ''"), "CLI translation should disable all Claude Code tools")
expect(command.contains("--strict-mcp-config"), "CLI translation should ignore ambient MCP configuration")
expect(command.contains("--mcp-config '{}'"), "CLI translation should use an empty MCP config")
expect(command.contains("--model 'claude-sonnet-4-6'"), "CLI translation should quote the model argument")
expect(command.contains("--append-system-prompt-file '/tmp/ec-test-prompt.txt'"), "CLI translation should pass the prompt file explicitly")

let workingDirectory = ClaudeCLITranslationProvider.isolatedWorkingDirectory()
let tempRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
expect(
    workingDirectory.standardizedFileURL.path.hasPrefix(tempRoot),
    "CLI translation should run from an isolated temporary directory"
)
expect(
    workingDirectory.lastPathComponent == "NovaClaudeCLI",
    "CLI translation should use a dedicated empty working directory"
)

print("ClaudeCLISafetyTests passed")
