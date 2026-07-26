import KeyboardShortcuts
import AppKit
import SwiftUI

@MainActor
enum SettingsWindowPresentationPolicy {
    static let level = NSWindow.Level.floating
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary
    ]

    /// 将设置窗口提升为跨空间浮动窗口并主动置前。
    static func apply(to window: NSWindow) {
        window.level = level
        window.collectionBehavior.insert(collectionBehavior)
        window.hidesOnDeactivate = false
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class SettingsWindowLevelView: NSView {
    /// 当视图进入设置窗口时，把窗口提升为跨空间浮动层级。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowLevel()
    }

    /// 将设置窗口置顶并确保它在全屏空间中也能显示。
    func configureWindowLevel() {
        guard let window else {
            return
        }
        SettingsWindowPresentationPolicy.apply(to: window)
    }
}

struct SettingsWindowLevelConfigurator: NSViewRepresentable {
    /// 创建用于配置宿主设置窗口的透明 AppKit 视图。
    func makeNSView(context: Context) -> SettingsWindowLevelView {
        SettingsWindowLevelView(frame: .zero)
    }

    /// 设置窗口重绘或重新出现时再次确认浮动层级。
    func updateNSView(
        _ nsView: SettingsWindowLevelView,
        context: Context
    ) {
        DispatchQueue.main.async {
            nsView.configureWindowLevel()
        }
    }
}

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

                Text("Finder 位于前台时打开当前目录；否则打开桌面。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !controller.isHotkeyRegistered {
                    Label(
                        "当前快捷键未生效，请重新录入一个未被占用的组合。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
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
                    "开机自启动",
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

            Section("更新") {
                Button {
                    controller.checkForUpdates()
                } label: {
                    HStack {
                        Label("检查 GitHub Release 更新", systemImage: "arrow.clockwise")
                        Spacer()
                        if controller.isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(controller.isCheckingForUpdates)

                Text(controller.updateStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 520)
        .background(SettingsWindowLevelConfigurator())
        .onAppear {
            controller.refreshSystemState()
            controller.refreshHotkeyRegistrationStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name(
                    "KeyboardShortcuts_shortcutByNameDidChange"
                )
            )
        ) { _ in
            controller.refreshHotkeyRegistrationStatus()
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
