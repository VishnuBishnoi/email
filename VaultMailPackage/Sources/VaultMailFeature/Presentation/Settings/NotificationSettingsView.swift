import SwiftUI

/// iOS navigation destination for notification settings.
///
/// Wraps `NotificationSettingsContent` in a navigation context with
/// proper title and list style.
///
/// Spec ref: NOTIF-23
struct NotificationSettingsView: View {
    @Environment(ThemeProvider.self) private var theme
    let accounts: [Account]

    var body: some View {
        NotificationSettingsContent(accounts: accounts)
            .navigationTitle("Notifications")
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
    }
}
