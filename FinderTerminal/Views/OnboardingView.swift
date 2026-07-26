import SwiftUI

struct OnboardingView: View {
    @ObservedObject var controller: AppController
    @State private var launchAtLogin: Bool

    /// 使用当前登录项状态初始化首次引导选项。
    init(controller: AppController) {
        self.controller = controller
        _launchAtLogin = State(initialValue: controller.isLaunchAtLoginEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Finder Terminal")
                        .font(.largeTitle.bold())
                    Text("从 Finder 一键打开当前目录")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("选中文件夹时打开该文件夹", systemImage: "folder")
                Label("选中文件时打开文件所在目录", systemImage: "doc")
                Label("未选择内容时打开当前 Finder 窗口目录", systemImage: "macwindow")
            }

            HStack {
                Text("默认快捷键")
                Spacer()
                Text(FinderTerminalShortcut.displayText)
                    .font(.system(.body, design: .monospaced).bold())
            }

            Text("旧版 ⌘⇧T 与 Finder 的标签页快捷键冲突，已自动更新。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("开机自启动 Finder Terminal", isOn: $launchAtLogin)

            Text("点击测试后，macOS 会询问是否允许本应用读取 Finder 当前路径。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("授权并测试") {
                    controller.runAuthorizationTest()
                }

                Spacer()

                Button("完成") {
                    controller.completeOnboarding(
                        launchAtLogin: launchAtLogin
                    )
                }
                .keyboardShortcut(.defaultAction)
            }

            Text(controller.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(28)
        .frame(width: 520, height: 420)
    }
}
