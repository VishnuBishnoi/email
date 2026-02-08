import SwiftUI

/// Placeholder view for email detail screen (future feature).
///
/// Shows the thread subject and a "Coming soon" message.
/// Will be replaced with full EmailDetailView in a future milestone.
///
/// Spec ref: Thread List spec FR-TL-05
struct EmailDetailPlaceholder: View {
    let threadSubject: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.open")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(threadSubject)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Email detail coming soon")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Email")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        EmailDetailPlaceholder(threadSubject: "Re: Meeting Notes from Tuesday")
    }
}
