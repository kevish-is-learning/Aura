import SwiftUI

@main
struct sexophoneApp: App {
    @AppStorage("playerVisibilityMode") private var visibilityMode: PlayerVisibilityMode = .lockScreenOnly

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Hide the title bar initially so it doesn't flash before our borderless config
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Sexophone", systemImage: "music.note") {
            VStack(alignment: .leading) {
                Text("Sexophone Display Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Button {
                    visibilityMode = .lockScreenOnly
                    notifyVisibilityChange()
                } label: {
                    Label(
                        "Lock Screen Only",
                        systemImage: visibilityMode == .lockScreenOnly ? "checkmark.circle.fill" : "lock.display"
                    )
                }

                Button {
                    visibilityMode = .alwaysOnScreen
                    notifyVisibilityChange()
                } label: {
                    Label(
                        "Always on All Screens",
                        systemImage: visibilityMode == .alwaysOnScreen ? "checkmark.circle.fill" : "display.on.fly"
                    )
                }

                Divider()

                Button("Bring Player to Front") {
                    if let window = NSApplication.shared.windows.first {
                        window.setIsVisible(true)
                        window.orderFrontRegardless()
                    }
                }

                Divider()

                Button("Quit Sexophone") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func notifyVisibilityChange() {
        NotificationCenter.default.post(name: NSNotification.Name("PlayerVisibilityModeChanged"), object: nil)
    }
}

