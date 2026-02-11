import SwiftUI
import SwiftData

/// Small colored dot indicating which account a thread belongs to in unified inbox mode.
///
/// Uses `AvatarView.color(for:)` to derive a deterministic color from the account's email
/// address, ensuring consistent visual association between threads and accounts.
///
/// Spec ref: Thread List spec FR-TL account indicator
struct AccountIndicatorView: View {
    let accountId: String
    let accounts: [Account]

    // MARK: - Constants

    private static let dotSize: CGFloat = 6

    // MARK: - Body

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: Self.dotSize, height: Self.dotSize)
            .accessibilityLabel(Text("Account: \(matchedAccount?.displayName ?? "Unknown")"))
    }

    // MARK: - Helpers

    private var matchedAccount: Account? {
        accounts.first { $0.id == accountId }
    }

    private var dotColor: Color {
        guard let account = matchedAccount else {
            return .clear
        }
        return AvatarView.color(for: account.email)
    }
}

// MARK: - Previews

#Preview("Account Indicator - Matched") {
    let account = Account(
        id: "acc-1",
        email: "alice@proton.me",
        displayName: "Alice Johnson"
    )
    return HStack(spacing: 8) {
        AccountIndicatorView(accountId: "acc-1", accounts: [account])
        Text("Thread subject line")
            .font(.subheadline)
    }
    .padding()
}

#Preview("Account Indicator - Multiple Accounts") {
    let accounts = [
        Account(id: "acc-1", email: "alice@proton.me", displayName: "Alice Johnson"),
        Account(id: "acc-2", email: "bob@gmail.com", displayName: "Bob Smith"),
        Account(id: "acc-3", email: "carol@work.org", displayName: "Carol Davis"),
    ]
    return VStack(alignment: .leading, spacing: 12) {
        ForEach(accounts, id: \.id) { account in
            HStack(spacing: 8) {
                AccountIndicatorView(accountId: account.id, accounts: accounts)
                Text(account.displayName)
                    .font(.subheadline)
            }
        }
    }
    .padding()
}

#Preview("Account Indicator - Unknown Account") {
    AccountIndicatorView(accountId: "nonexistent", accounts: [])
        .padding()
}
