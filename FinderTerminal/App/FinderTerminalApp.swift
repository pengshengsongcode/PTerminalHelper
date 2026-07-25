import SwiftUI

@main
struct FinderTerminalApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra(
            "Finder Terminal",
            systemImage: "terminal"
        ) {
            MenuBarContentView(controller: controller)
        }

        Settings {
            SettingsView(controller: controller)
        }
    }
}
