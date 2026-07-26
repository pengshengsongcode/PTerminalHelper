import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings

    /// 绑定应用控制器和用户设置，确保菜单状态实时刷新。
    init(controller: AppController) {
        self.controller = controller
        settings = controller.settings
    }

    var body: some View {
        Button {
            controller.openFromMenu()
        } label: {
            Label("在终端中打开", systemImage: "terminal")
        }
        .keyboardShortcut("o")

        Divider()

        Text("默认终端：\(settings.selectedTerminal.displayName)")

        if !controller.isHotkeyRegistered {
            Label(
                "快捷键未生效，请在设置中修改",
                systemImage: "exclamationmark.triangle.fill"
            )
        }

        if !controller.statusMessage.isEmpty {
            Text(controller.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        Divider()

        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("设置…")
            }
            .keyboardShortcut(",")
        } else {
            Button("设置…") {
                controller.showLegacySettings()
            }
            .keyboardShortcut(",")
        }

        Button("退出 Finder Terminal") {
            controller.quitApplication()
        }
        .keyboardShortcut("q")
    }
}
