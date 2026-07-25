import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings

    /// 绑定应用控制器和可持久化设置。
    init(controller: AppController) {
        self.controller = controller
        settings = controller.settings
    }

    var body: some View {
        Form {
            Section("快捷键") {
                KeyboardShortcuts.Recorder(
                    "从 Finder 打开终端",
                    name: .openFinderTerminal
                )

                Text("快捷键只会在 Finder 位于前台时执行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("终端") {
                Picker(
                    "默认终端",
                    selection: terminalSelection
                ) {
                    ForEach(controller.installedTerminals) { terminal in
                        Text(terminal.displayName).tag(terminal)
                    }
                }

                if !controller.installedTerminals.contains(settings.selectedTerminal) {
                    Text("原默认终端已卸载，执行时会回退到系统“终端”。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("启动与权限") {
                Toggle(
                    "登录时启动",
                    isOn: launchAtLoginBinding
                )

                if controller.launchAtLoginStatus == .requiresApproval {
                    Button("打开登录项设置") {
                        controller.openLoginItemsSettings()
                    }
                }

                Button("授权并测试打开") {
                    controller.runAuthorizationTest()
                }

                Text("首次测试时，macOS 会请求允许 Finder Terminal 控制 Finder。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("状态") {
                Text(controller.statusMessage)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 430)
        .onAppear {
            controller.refreshSystemState()
        }
    }

    private var terminalSelection: Binding<TerminalKind> {
        Binding(
            get: { settings.selectedTerminal },
            set: { controller.selectTerminal($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { controller.isLaunchAtLoginEnabled },
            set: { controller.setLaunchAtLogin($0) }
        )
    }
}
