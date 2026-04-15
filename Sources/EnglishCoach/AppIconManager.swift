import AppKit
import Foundation

@MainActor
final class AppIconManager {
    enum LearningIconState {
        case pending
        case completed
    }

    private let pendingIcon: NSImage?
    private let completedIcon: NSImage?
    private let completedGlowIcon: NSImage?

    private var currentState: LearningIconState?
    private var animationTask: Task<Void, Never>?

    init(bundle: Bundle = .main) {
        pendingIcon = Self.loadIcon(resource: "AppIconPending", bundle: bundle)
        completedIcon = Self.loadIcon(resource: "AppIconCompleted", bundle: bundle)
        completedGlowIcon = Self.loadIcon(resource: "AppIconCompletedGlow", bundle: bundle)
    }

    deinit {
        animationTask?.cancel()
    }

    func applyLearningState(completedToday: Bool, animateTransition: Bool) {
        let targetState: LearningIconState = completedToday ? .completed : .pending

        if currentState == targetState, !animateTransition {
            return
        }

        currentState = targetState
        animationTask?.cancel()

        if completedToday, animateTransition {
            runCompletionPulseAnimation()
        } else {
            applyDockIcon(for: targetState)
        }
    }

    private func applyDockIcon(for state: LearningIconState) {
        let icon: NSImage?
        switch state {
        case .pending:
            icon = pendingIcon
        case .completed:
            icon = completedIcon ?? pendingIcon
        }

        if let icon {
            NSApp.applicationIconImage = icon
        }
    }

    private func runCompletionPulseAnimation() {
        let frames: [NSImage?] = [
            pendingIcon,
            completedIcon,
            completedGlowIcon ?? completedIcon,
            completedIcon,
            completedGlowIcon ?? completedIcon,
            completedIcon
        ]

        animationTask = Task { @MainActor in
            for (index, frame) in frames.enumerated() {
                if Task.isCancelled { return }
                if let frame {
                    NSApp.applicationIconImage = frame
                }
                if index < frames.count - 1 {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }
        }
    }

    private static func loadIcon(resource: String, bundle: Bundle) -> NSImage? {
        guard let iconURL = bundle.url(forResource: resource, withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: iconURL)
    }
}
