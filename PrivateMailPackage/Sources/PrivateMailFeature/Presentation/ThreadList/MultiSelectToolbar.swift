import SwiftUI

/// Bottom toolbar for batch actions when the thread list is in multi-select mode.
///
/// Shows a count of selected threads and a row of icon buttons for common
/// batch operations (archive, delete, read, unread, star, move). All buttons
/// are disabled when no threads are selected.
///
/// Spec ref: Thread List spec FR-TL-03
struct MultiSelectToolbar: View {
    let selectedCount: Int
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onMarkRead: () -> Void
    let onMarkUnread: () -> Void
    let onStar: () -> Void
    let onMove: () -> Void

    private var isDisabled: Bool {
        selectedCount == 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                Text("\(selectedCount) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    toolbarButton(
                        icon: "archivebox",
                        label: "Archive",
                        action: onArchive
                    )

                    Spacer()

                    toolbarButton(
                        icon: "trash",
                        label: "Delete",
                        action: onDelete
                    )

                    Spacer()

                    toolbarButton(
                        icon: "envelope.open",
                        label: "Mark Read",
                        action: onMarkRead
                    )

                    Spacer()

                    toolbarButton(
                        icon: "envelope.badge",
                        label: "Mark Unread",
                        action: onMarkUnread
                    )

                    Spacer()

                    toolbarButton(
                        icon: "star",
                        label: "Star",
                        action: onStar
                    )

                    Spacer()

                    toolbarButton(
                        icon: "folder",
                        label: "Move",
                        action: onMove
                    )
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: - Toolbar Button

    private func toolbarButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
        }
        .disabled(isDisabled)
        .accessibilityLabel(label)
        .accessibilityHint(
            isDisabled
                ? "No threads selected"
                : "\(label) \(selectedCount) selected thread\(selectedCount == 1 ? "" : "s")"
        )
    }
}

// MARK: - Previews

#Preview("No Selection") {
    VStack {
        Spacer()
        MultiSelectToolbar(
            selectedCount: 0,
            onArchive: {},
            onDelete: {},
            onMarkRead: {},
            onMarkUnread: {},
            onStar: {},
            onMove: {}
        )
    }
}

#Preview("3 Selected") {
    VStack {
        Spacer()
        MultiSelectToolbar(
            selectedCount: 3,
            onArchive: {},
            onDelete: {},
            onMarkRead: {},
            onMarkUnread: {},
            onStar: {},
            onMove: {}
        )
    }
}

#Preview("1 Selected") {
    VStack {
        Spacer()
        MultiSelectToolbar(
            selectedCount: 1,
            onArchive: {},
            onDelete: {},
            onMarkRead: {},
            onMarkUnread: {},
            onStar: {},
            onMove: {}
        )
    }
}
