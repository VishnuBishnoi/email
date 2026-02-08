import Foundation

public enum UndoSendPhase: Equatable, Sendable {
    case composing
    case undoWindow(secondsRemaining: Int)
    case queuedForSMTP
    case sending
    case sent
    case failed
    case draft
}

public struct UndoSendStateMachine: Sendable {
    public private(set) var phase: UndoSendPhase = .composing
    private var isPausedInBackground = false

    public init() {}

    public var sendState: SendState {
        switch phase {
        case .composing, .draft:
            return .none
        case .undoWindow, .queuedForSMTP:
            return .queued
        case .sending:
            return .sending
        case .sent:
            return .sent
        case .failed:
            return .failed
        }
    }

    public var isDraft: Bool {
        switch phase {
        case .composing, .draft:
            return true
        default:
            return false
        }
    }

    public mutating func start(delaySeconds: Int) {
        if delaySeconds <= 0 {
            phase = .queuedForSMTP
            return
        }

        phase = .undoWindow(secondsRemaining: delaySeconds)
        isPausedInBackground = false
    }

    public mutating func tick(seconds: Int = 1) {
        guard case .undoWindow(let remaining) = phase else { return }
        guard !isPausedInBackground else { return }

        let next = max(0, remaining - max(0, seconds))
        phase = next == 0 ? .queuedForSMTP : .undoWindow(secondsRemaining: next)
    }

    public mutating func undo() {
        guard case .undoWindow = phase else { return }
        phase = .draft
    }

    public mutating func background() {
        guard case .undoWindow = phase else { return }
        isPausedInBackground = true
    }

    public mutating func foreground() {
        guard case .undoWindow = phase else { return }
        isPausedInBackground = false
    }

    public mutating func terminate() {
        guard case .undoWindow = phase else { return }
        phase = .draft
        isPausedInBackground = false
    }

    public mutating func networkBecameOffline() {
        // No state transition required during undo window; timer behavior is unchanged.
    }

    public mutating func beginSending() {
        guard case .queuedForSMTP = phase else { return }
        phase = .sending
    }

    public mutating func markSent() {
        phase = .sent
    }

    public mutating func markFailed() {
        phase = .failed
    }
}
