import Foundation
import SwiftData

/// Seeds the SwiftData store with sample data for debugging the thread list.
///
/// **DEBUG ONLY** — This file should be excluded from release builds.
/// Inserts a realistic set of accounts, folders, threads, emails, and
/// email-folder join records so the thread list UI can be exercised.
#if DEBUG
@MainActor
public enum DebugDataSeeder {

    /// Seed the database if it's empty (idempotent).
    public static func seedIfNeeded(modelContext: ModelContext) {
        // Check if we already have threads — skip if data exists
        let descriptor = FetchDescriptor<VaultMailFeature.Thread>()
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        // Also check we have an account
        let accountDescriptor = FetchDescriptor<Account>()
        let accounts = (try? modelContext.fetch(accountDescriptor)) ?? []
        guard let account = accounts.first else { return }

        // Create Inbox folder if missing
        let folderDescriptor = FetchDescriptor<Folder>()
        let existingFolders = (try? modelContext.fetch(folderDescriptor)) ?? []

        let inbox: Folder
        if let existing = existingFolders.first(where: { $0.folderType == FolderType.inbox.rawValue }) {
            inbox = existing
        } else {
            inbox = Folder(
                name: "Inbox",
                imapPath: "INBOX",
                folderType: FolderType.inbox.rawValue
            )
            inbox.account = account
            modelContext.insert(inbox)
        }

        // Create additional system folders
        let systemFolders: [(String, String, FolderType)] = [
            ("Sent", "[Gmail]/Sent Mail", .sent),
            ("Drafts", "[Gmail]/Drafts", .drafts),
            ("Trash", "[Gmail]/Trash", .trash),
            ("Spam", "[Gmail]/Spam", .spam),
            ("Starred", "[Gmail]/Starred", .starred),
            ("Archive", "[Gmail]/All Mail", .archive),
        ]

        for (name, path, type) in systemFolders {
            if !existingFolders.contains(where: { $0.folderType == type.rawValue }) {
                let folder = Folder(name: name, imapPath: path, folderType: type.rawValue)
                folder.account = account
                modelContext.insert(folder)
            }
        }

        // Create sample threads and emails
        let sampleData: [(subject: String, sender: String, senderEmail: String, snippet: String, category: AICategory, unread: Int, starred: Bool, minutesAgo: Int, messageCount: Int)] = [
            (
                subject: "Q4 Revenue Report — Final Review",
                sender: "Sarah Chen",
                senderEmail: "sarah.chen@company.com",
                snippet: "Hi team, please review the attached Q4 report before our Friday meeting. Key highlights include a 15% YoY growth in...",
                category: .primary,
                unread: 2,
                starred: true,
                minutesAgo: 5,
                messageCount: 4
            ),
            (
                subject: "Your order has shipped!",
                sender: "Amazon",
                senderEmail: "ship-confirm@amazon.com",
                snippet: "Your package is on its way! Track your delivery: Expected arrival Tuesday, Feb 11.",
                category: .promotions,
                unread: 1,
                starred: false,
                minutesAgo: 30,
                messageCount: 1
            ),
            (
                subject: "Weekend hiking trip?",
                sender: "Mike Johnson",
                senderEmail: "mike.j@gmail.com",
                snippet: "Hey! Are we still on for the hike this Saturday? I was thinking we could try that new trail near...",
                category: .social,
                unread: 1,
                starred: false,
                minutesAgo: 120,
                messageCount: 3
            ),
            (
                subject: "Your monthly bank statement is ready",
                sender: "Chase Bank",
                senderEmail: "no-reply@chase.com",
                snippet: "Your January 2026 statement is now available. Log in to view your account activity and balance summary.",
                category: .updates,
                unread: 0,
                starred: false,
                minutesAgo: 300,
                messageCount: 1
            ),
            (
                subject: "Re: Design system migration plan",
                sender: "Alex Rivera",
                senderEmail: "alex.rivera@company.com",
                snippet: "I've updated the Figma file with the new component library. Can you take a look at the button variants?",
                category: .primary,
                unread: 0,
                starred: true,
                minutesAgo: 1440,
                messageCount: 8
            ),
            (
                subject: "[Swift Forums] Structured Concurrency Proposal",
                sender: "Swift Forums",
                senderEmail: "notifications@forums.swift.org",
                snippet: "New reply from @hollyb: I think the task group API could benefit from a cleaner cancellation pattern...",
                category: .forums,
                unread: 3,
                starred: false,
                minutesAgo: 2880,
                messageCount: 12
            ),
            (
                subject: "50% off Premium — Limited Time Offer",
                sender: "Spotify",
                senderEmail: "no-reply@spotify.com",
                snippet: "Upgrade to Spotify Premium today and get 50% off your first 3 months. Stream ad-free music anywhere.",
                category: .promotions,
                unread: 1,
                starred: false,
                minutesAgo: 4320,
                messageCount: 1
            ),
            (
                subject: "Team standup notes — Feb 5",
                sender: "Emily Park",
                senderEmail: "emily.park@company.com",
                snippet: "Notes from today's standup: 1) Backend API migration on track for next sprint. 2) iOS thread list feature...",
                category: .primary,
                unread: 0,
                starred: false,
                minutesAgo: 5760,
                messageCount: 2
            ),
            (
                subject: "New sign-in from Chrome on Mac",
                sender: "Google",
                senderEmail: "no-reply@accounts.google.com",
                snippet: "A new sign-in was detected on your Google Account. If this was you, no action is needed.",
                category: .updates,
                unread: 0,
                starred: false,
                minutesAgo: 7200,
                messageCount: 1
            ),
            (
                subject: "Photos from the team dinner",
                sender: "Jessica Lee",
                senderEmail: "jessica.lee@gmail.com",
                snippet: "Here are the photos from last night! Great time everyone. The group photo turned out really well 📸",
                category: .social,
                unread: 0,
                starred: true,
                minutesAgo: 10080,
                messageCount: 5
            ),
            (
                subject: "Invoice #2024-1587 — Payment Received",
                sender: "Stripe",
                senderEmail: "receipts@stripe.com",
                snippet: "Payment of $49.99 received for your subscription renewal. Your next billing date is March 8, 2026.",
                category: .updates,
                unread: 0,
                starred: false,
                minutesAgo: 14400,
                messageCount: 1
            ),
            (
                subject: "Re: Apartment lease renewal",
                sender: "Property Manager",
                senderEmail: "leasing@apartments.com",
                snippet: "Thank you for confirming your lease renewal. The updated agreement is attached for your records.",
                category: .primary,
                unread: 0,
                starred: true,
                minutesAgo: 20160,
                messageCount: 6
            ),
        ]

        let calendar = Calendar.current

        for (index, data) in sampleData.enumerated() {
            let threadDate = calendar.date(byAdding: .minute, value: -data.minutesAgo, to: .now) ?? .now

            let participants = Participant.encode([
                Participant(name: data.sender, email: data.senderEmail)
            ])

            // Create Thread
            let thread = VaultMailFeature.Thread(
                id: "debug-thread-\(index)",
                accountId: account.id,
                subject: data.subject,
                latestDate: threadDate,
                messageCount: data.messageCount,
                unreadCount: data.unread,
                isStarred: data.starred,
                aiCategory: data.category.rawValue,
                snippet: data.snippet,
                participants: participants
            )
            modelContext.insert(thread)

            // Create Email for the thread (at minimum one per thread for the join to work)
            let email = Email(
                id: "debug-email-\(index)",
                accountId: account.id,
                threadId: thread.id,
                messageId: "<debug-\(index)@vaultmail.test>",
                fromAddress: data.senderEmail,
                fromName: data.sender,
                toAddresses: "[\"user@gmail.com\"]",
                subject: data.subject,
                snippet: data.snippet,
                dateReceived: threadDate,
                isRead: data.unread == 0,
                isStarred: data.starred,
                aiCategory: data.category.rawValue
            )
            email.thread = thread
            modelContext.insert(email)

            // Create EmailFolder join to link email to inbox
            let emailFolder = EmailFolder(
                id: "debug-ef-\(index)",
                imapUID: 1000 + index
            )
            emailFolder.email = email
            emailFolder.folder = inbox
            modelContext.insert(emailFolder)
        }

        // Update inbox unread count
        inbox.unreadCount = sampleData.reduce(0) { $0 + $1.unread }
        inbox.totalCount = sampleData.count

        // Save
        try? modelContext.save()

        print("[DebugDataSeeder] Seeded \(sampleData.count) threads for account: \(account.email)")
    }
}
#endif
