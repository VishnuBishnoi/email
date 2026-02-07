import SwiftUI

/// Root content view — launches to an empty screen for foundation (AC-F-01).
public struct ContentView: View {
    public var body: some View {
        NavigationStack {
            Text("PrivateMail")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .navigationTitle("PrivateMail")
        }
    }

    public init() {}
}
