import SwiftUI

/// Shared notification settings content for iOS and macOS.
///
/// 6 sections: System Permission, Per-Account Toggles, Categories,
/// VIP Contacts, Muted Threads, Quiet Hours.
///
/// Spec ref: NOTIF-09, NOTIF-10, NOTIF-11, NOTIF-14, NOTIF-23
public struct NotificationSettingsContent: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme
    @Environment(NotificationSyncCoordinator.self) private var coordinator: NotificationSyncCoordinator?

    let accounts: [Account]

    @State private var authStatus: NotificationAuthStatus = .notDetermined
    @State private var newVIPEmail = ""
    #if DEBUG
    @State private var debugStatus: String?
    #endif

    public init(accounts: [Account]) {
        self.accounts = accounts
    }

    public var body: some View {
        Form {
            systemPermissionSection
            accountsSection
            categoriesSection
            vipContactsSection
            mutedThreadsSection
            quietHoursSection
            #if DEBUG
            debugSection
            #endif
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .task {
            await checkAuthStatus()
        }
    }

    // MARK: - System Permission Section

    @ViewBuilder
    private var systemPermissionSection: some View {
        Section {
            HStack {
                Label(authStatusLabel, systemImage: authStatusIcon)
                    .foregroundStyle(authStatusColor)
                Spacer()
                if authStatus == .notDetermined {
                    Button("Enable") {
                        Task { await requestPermission() }
                    }
                }
                #if os(iOS)
                if authStatus == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(theme.typography.bodyMedium)
                }
                #endif
            }
        } header: {
            Text("System Permission")
        }
    }

    private var authStatusLabel: String {
        switch authStatus {
        case .authorized, .provisional: "Notifications Enabled"
        case .denied: "Notifications Disabled in System Settings"
        case .notDetermined: "Notifications Not Yet Requested"
        }
    }

    private var authStatusIcon: String {
        switch authStatus {
        case .authorized, .provisional: "bell.badge.fill"
        case .denied: "bell.slash.fill"
        case .notDetermined: "bell"
        }
    }

    private var authStatusColor: Color {
        switch authStatus {
        case .authorized, .provisional: theme.colors.success
        case .denied: theme.colors.warning
        case .notDetermined: theme.colors.textSecondary
        }
    }

    // MARK: - Accounts Section (NOTIF-09)

    @ViewBuilder
    private var accountsSection: some View {
        Section("Accounts") {
            if accounts.isEmpty {
                Text("No accounts configured.")
                    .foregroundStyle(theme.colors.textSecondary)
            } else {
                ForEach(accounts, id: \.id) { account in
                    Toggle(account.email, isOn: Binding(
                        get: { settings.notificationsEnabled(for: account.id) },
                        set: { settings.notificationPreferences[account.id] = $0 }
                    ))
                    .accessibilityLabel("Notifications for \(account.email)")
                }
            }
        }
    }

    // MARK: - Categories Section (NOTIF-09)

    @ViewBuilder
    private var categoriesSection: some View {
        Section {
            ForEach(toggleableCategories, id: \.0) { key, label in
                Toggle(label, isOn: Binding(
                    get: { settings.notificationCategoryEnabled(for: key) },
                    set: { settings.notificationCategoryPreferences[key] = $0 }
                ))
                .accessibilityLabel("Notifications for \(label) category")
            }
        } header: {
            Text("Categories")
        } footer: {
            Text("Choose which email categories trigger notifications.")
        }
    }

    private var toggleableCategories: [(String, String)] {
        [
            (AICategory.primary.rawValue, "Primary"),
            (AICategory.social.rawValue, "Social"),
            (AICategory.promotions.rawValue, "Promotions"),
            (AICategory.updates.rawValue, "Updates"),
        ]
    }

    // MARK: - VIP Contacts Section (NOTIF-10)

    @ViewBuilder
    private var vipContactsSection: some View {
        Section {
            ForEach(Array(settings.vipContacts).sorted(), id: \.self) { email in
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(theme.colors.starred)
                        .accessibilityHidden(true)
                    Text(email)
                }
                .swipeActions(edge: .trailing) {
                    Button("Remove", role: .destructive) {
                        settings.removeVIPContact(email)
                    }
                }
                .accessibilityLabel("VIP contact: \(email)")
            }

            HStack {
                TextField("Add VIP email", text: $newVIPEmail)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    #endif
                    .accessibilityLabel("VIP email address")

                Button("Add") {
                    let trimmed = newVIPEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    settings.addVIPContact(trimmed)
                    newVIPEmail = ""
                }
                .disabled(newVIPEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("VIP Contacts")
        } footer: {
            Text("VIP contacts always trigger notifications, even during quiet hours or when their category is disabled.")
        }
    }

    // MARK: - Muted Threads Section (NOTIF-11)

    @ViewBuilder
    private var mutedThreadsSection: some View {
        Section {
            if settings.mutedThreadIds.isEmpty {
                Text("No muted threads.")
                    .foregroundStyle(theme.colors.textSecondary)
            } else {
                ForEach(Array(settings.mutedThreadIds).sorted(), id: \.self) { threadId in
                    HStack {
                        Image(systemName: "bell.slash")
                            .foregroundStyle(theme.colors.textSecondary)
                            .accessibilityHidden(true)
                        Text(threadId)
                            .lineLimit(1)
                            .font(theme.typography.captionMono)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Unmute") {
                            settings.toggleMuteThread(threadId: threadId)
                        }
                    }
                    .accessibilityLabel("Muted thread")
                }
            }
        } header: {
            Text("Muted Threads")
        } footer: {
            Text("Muted threads will never trigger notifications. Swipe to unmute.")
        }
    }

    // MARK: - Quiet Hours Section (NOTIF-14)

    @ViewBuilder
    private var quietHoursSection: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Enable Quiet Hours", isOn: $settings.quietHoursEnabled)
                .accessibilityLabel("Quiet hours")

            if settings.quietHoursEnabled {
                DatePicker(
                    "Start",
                    selection: Binding(
                        get: { minutesToDate(settings.quietHoursStart) },
                        set: { settings.quietHoursStart = dateToMinutes($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityLabel("Quiet hours start time")

                DatePicker(
                    "End",
                    selection: Binding(
                        get: { minutesToDate(settings.quietHoursEnd) },
                        set: { settings.quietHoursEnd = dateToMinutes($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityLabel("Quiet hours end time")
            }
        } header: {
            Text("Quiet Hours")
        } footer: {
            Text("Notifications are silenced during quiet hours. VIP contacts override this setting.")
        }
    }

    // MARK: - Debug Section

    #if DEBUG
    @ViewBuilder
    private var debugSection: some View {
        Section {
            Button {
                Task { await sendTestNotification(category: .primary) }
            } label: {
                Label("Send Test Notification", systemImage: "bell.badge")
            }

            Button {
                Task { await sendBatchTestNotifications() }
            } label: {
                Label("Send Batch (5 emails)", systemImage: "bell.badge.waveform")
            }

            Button {
                Task { await sendVIPTestNotification() }
            } label: {
                Label("Send VIP Test", systemImage: "star.fill")
            }

            Button {
                Task { await runFilterDiagnostics() }
            } label: {
                Label("Test Filter Pipeline", systemImage: "line.3.horizontal.decrease.circle")
            }

            Button(role: .destructive) {
                Task { await clearAllNotifications() }
            } label: {
                Label("Clear All Notifications", systemImage: "trash")
            }

            if let debugStatus {
                Text(debugStatus)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Test notifications respect your current filter settings (account, category, quiet hours, VIP).")
        }
    }

    private func makeDebugEmail(
        fromName: String,
        fromAddress: String,
        subject: String,
        snippet: String,
        category: AICategory
    ) -> Email {
        let accountId = accounts.first?.id ?? "debug-account"
        return Email(
            accountId: accountId,
            threadId: UUID().uuidString,
            messageId: "<debug-\(UUID().uuidString)@test.local>",
            fromAddress: fromAddress,
            fromName: fromName,
            subject: subject,
            snippet: snippet,
            dateReceived: Date(),
            aiCategory: category.rawValue
        )
    }

    private func sendTestNotification(category: AICategory) async {
        guard let coordinator else { debugStatus = "Coordinator not available"; return }
        let email = makeDebugEmail(
            fromName: "Test Sender",
            fromAddress: "test@example.com",
            subject: "Test Notification",
            snippet: "This is a test notification to verify delivery is working correctly.",
            category: category
        )
        await coordinator.sendDebugNotification(from: email)
        debugStatus = "Sent test notification (\(category.rawValue))"
    }

    private func sendBatchTestNotifications() async {
        guard let coordinator else { debugStatus = "Coordinator not available"; return }
        let testEmails: [(String, String, String, AICategory)] = [
            ("Alice Smith", "alice@work.com", "Q1 Planning Meeting", .primary),
            ("Bob from Twitter", "notifications@twitter.com", "New follower", .social),
            ("Amazon", "deals@amazon.com", "Flash sale today", .promotions),
            ("GitHub", "noreply@github.com", "PR review requested", .updates),
            ("Carol Jones", "carol@team.com", "Project update", .primary),
        ]

        var sentCount = 0
        for (name, address, subject, category) in testEmails {
            let email = makeDebugEmail(
                fromName: name,
                fromAddress: address,
                subject: subject,
                snippet: "Debug batch test email from \(name).",
                category: category
            )
            await coordinator.sendDebugNotification(from: email)
            sentCount += 1
        }
        debugStatus = "Sent \(sentCount) test notifications"
    }

    private func sendVIPTestNotification() async {
        guard let coordinator else { debugStatus = "Coordinator not available"; return }
        let vipAddress = settings.vipContacts.first ?? "vip@example.com"
        let email = makeDebugEmail(
            fromName: "VIP Contact",
            fromAddress: vipAddress,
            subject: "VIP Test Message",
            snippet: "This notification should bypass all filters except account check.",
            category: .primary
        )
        await coordinator.sendDebugNotification(from: email)
        debugStatus = "Sent VIP test (from: \(vipAddress))"
    }

    private func runFilterDiagnostics() async {
        guard let coordinator else { debugStatus = "Coordinator not available"; return }
        let email = makeDebugEmail(
            fromName: "Filter Test",
            fromAddress: "filter-test@example.com",
            subject: "Filter Diagnostics",
            snippet: "Testing which filters this email passes.",
            category: .primary
        )
        let result = await coordinator.diagnoseFilter(for: email)
        debugStatus = result
    }

    private func clearAllNotifications() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        try? await center.setBadgeCount(0)
        debugStatus = "Cleared all notifications and badge"
        #endif
    }
    #endif

    // MARK: - Helpers

    private func checkAuthStatus() async {
        // Use the notification service from environment if available,
        // otherwise fall back to checking UNUserNotificationCenter directly.
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let notifSettings = await center.notificationSettings()
        switch notifSettings.authorizationStatus {
        case .notDetermined: authStatus = .notDetermined
        case .authorized: authStatus = .authorized
        case .denied: authStatus = .denied
        case .provisional: authStatus = .provisional
        @unknown default: authStatus = .denied
        }
        #endif
    }

    private func requestPermission() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        await checkAuthStatus()
        #endif
    }

    private func minutesToDate(_ minutes: Int) -> Date {
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func dateToMinutes(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

#if canImport(UserNotifications)
import UserNotifications
#endif
