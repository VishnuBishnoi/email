#if os(macOS)
import SwiftUI

/// Menu bar commands + keyboard shortcuts for the macOS email client.
///
/// Provides File, Message, and View menu groups with keyboard shortcuts
/// for all common email actions. Action state (enabled/disabled) is driven
/// by `MacCommandState` environment values.
///
/// Spec ref: FR-MAC-07 (Keyboard Shortcuts)
public struct AppCommands: Commands {
    /// Shared state object for enabling/disabling thread-dependent actions.
    @FocusedValue(\.macCommandState) private var commandState

    public init() {}

    public var body: some Commands {
        // MARK: - File Menu

        CommandGroup(after: .newItem) {
            Button("New Email") {
                commandState?.onCompose()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(commandState == nil)
        }

        // MARK: - Message Menu

        CommandMenu("Message") {
            Button("Reply") {
                commandState?.onReply()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(commandState?.hasSelection != true)

            Button("Reply All") {
                commandState?.onReplyAll()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(commandState?.hasSelection != true)

            Button("Forward") {
                commandState?.onForward()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(commandState?.hasSelection != true)

            Divider()

            Button("Archive") {
                commandState?.onArchive()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(commandState?.hasSelection != true)

            Button("Delete") {
                commandState?.onDelete()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(commandState?.hasSelection != true)

            Button("Move to Folder…") {
                commandState?.onMove()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(commandState?.hasSelection != true)

            Divider()

            Button("Mark as Read/Unread") {
                commandState?.onToggleRead()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(commandState?.hasSelection != true)

            Button("Star/Unstar") {
                commandState?.onToggleStar()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(commandState?.hasSelection != true)
        }

        // MARK: - View Menu

        CommandGroup(after: .sidebar) {
            Button("Refresh") {
                commandState?.onSync()
            }
            .keyboardShortcut("r", modifiers: [.control, .shift])
        }
    }
}

// MARK: - Command State

/// Observable state shared between the main view and menu bar commands.
///
/// The main view sets these closures and the `hasSelection` flag
/// so menu items enable/disable correctly.
@MainActor @Observable
final class MacCommandState {
    var hasSelection: Bool = false

    var onCompose: () -> Void = {}
    var onReply: () -> Void = {}
    var onReplyAll: () -> Void = {}
    var onForward: () -> Void = {}
    var onArchive: () -> Void = {}
    var onDelete: () -> Void = {}
    var onMove: () -> Void = {}
    var onToggleRead: () -> Void = {}
    var onToggleStar: () -> Void = {}
    var onSync: () -> Void = {}
}

// MARK: - FocusedValue Key

struct MacCommandStateKey: FocusedValueKey {
    typealias Value = MacCommandState
}

extension FocusedValues {
    var macCommandState: MacCommandState? {
        get { self[MacCommandStateKey.self] }
        set { self[MacCommandStateKey.self] = newValue }
    }
}
#endif
