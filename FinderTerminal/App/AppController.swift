import AppKit
import KeyboardShortcuts
import os
import SwiftUI

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var installedTerminals: [TerminalKind] = []
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    @Published private(set) var isHotkeyRegistered = false
    @Published private(set) var statusMessage = "等待从 Finder 打开目录"

    let settings: AppSettings

    private let finderPathResolver: any FinderPathResolving
    private let terminalLauncher: any TerminalLaunching
    private let launchAtLoginController: any LaunchAtLoginManaging
    private let frontmostApplicationProvider: any FrontmostApplicationProviding
    private let logger = Logger(
        subsystem: "com.pengshengsong.FinderTerminal",
        category: "应用控制"
    )

    private var onboardingWindowController: NSWindowController?

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginStatus.isRequestedEnabled
    }

    /// 组合默认服务，并注册 Finder 专用全局快捷键。
    init(
        settings: AppSettings = AppSettings(),
        finderPathResolver: any FinderPathResolving = DefaultFinderPathResolver(),
        terminalLauncher: any TerminalLaunching = DefaultTerminalLauncher(),
        launchAtLoginController: any LaunchAtLoginManaging = DefaultLaunchAtLoginController(),
        frontmostApplicationProvider: any FrontmostApplicationProviding =
            NSWorkspaceFrontmostApplicationProvider()
    ) {
        self.settings = settings
        self.finderPathResolver = finderPathResolver
        self.terminalLauncher = terminalLauncher
        self.launchAtLoginController = launchAtLoginController
        self.frontmostApplicationProvider = frontmostApplicationProvider

        let didMigrateShortcut =
            FinderTerminalShortcut.migrateLegacyDefaultIfNeeded()
        if didMigrateShortcut {
            statusMessage = "默认快捷键已更新为 \(FinderTerminalShortcut.displayText)"
        }

        refreshSystemState()
        registerHotkey()

        DispatchQueue.main.async { [weak self] in
            self?.refreshHotkeyRegistrationStatus()
            self?.presentOnboardingIfNeeded()
        }
    }

    /// 注册快捷键抬起事件，避免按住按键时重复创建终端窗口。
    private func registerHotkey() {
        KeyboardShortcuts.onKeyUp(for: .openFinderTerminal) { [weak self] in
            Task { @MainActor in
                await self?.handleHotkey()
            }
        }
    }

    /// 检查当前快捷键是否已被系统成功注册，并为冲突或未设置状态给出提示。
    func refreshHotkeyRegistrationStatus() {
        let shortcut = KeyboardShortcuts.getShortcut(
            for: .openFinderTerminal
        )
        isHotkeyRegistered = KeyboardShortcuts.isEnabled(
            for: .openFinderTerminal
        )

        guard shortcut != nil else {
            statusMessage = "尚未设置全局快捷键"
            logger.notice("当前没有设置全局快捷键")
            return
        }

        guard isHotkeyRegistered else {
            statusMessage = "快捷键注册失败，可能已被其他应用占用，请在设置中修改"
            logger.error("全局快捷键注册失败，可能存在快捷键冲突")
            return
        }

        logger.info("全局快捷键已成功注册")
    }

    /// 检查 Finder 是否位于前台，并在符合条件时执行打开操作。
    private func handleHotkey() async {
        let bundleIdentifier = frontmostApplicationProvider.bundleIdentifier()
        guard ShortcutPolicy.shouldHandle(
            frontmostBundleIdentifier: bundleIdentifier
        ) else {
            logger.debug("前台应用不是 Finder，已忽略快捷键")
            return
        }

        _ = await openCurrentFinderDirectory()
    }

    /// 从菜单栏直接读取 Finder 状态并打开终端，不要求 Finder 仍是前台应用。
    func openFromMenu() {
        Task {
            _ = await openCurrentFinderDirectory()
        }
    }

    /// 执行首次引导或设置页中的权限与打开测试。
    func runAuthorizationTest() {
        Task {
            let succeeded = await openCurrentFinderDirectory()
            if succeeded {
                statusMessage = "授权与终端打开测试成功"
            }
        }
    }

    /// 解析 Finder 目录、启动终端并统一处理回退与错误。
    @discardableResult
    private func openCurrentFinderDirectory() async -> Bool {
        do {
            statusMessage = "正在读取 Finder 路径…"
            let resolution = try await finderPathResolver.resolveDirectory()
            let launchResult = try await terminalLauncher.openNewWindow(
                at: resolution.directoryURL,
                using: settings.selectedTerminal
            )

            statusMessage = "已在 \(launchResult.launchedTerminal.displayName) 打开 \(resolution.directoryURL.path)"

            if launchResult.didFallback {
                presentAlert(
                    title: "已回退系统终端",
                    message: "\(launchResult.requestedTerminal.displayName) 未安装，已改用系统“终端”。",
                    style: .informational
                )
            }
            return true
        } catch {
            let message = error.localizedDescription
            statusMessage = message
            logger.error("执行打开终端失败：\(message, privacy: .public)")
            presentAlert(
                title: "无法打开终端",
                message: message,
                style: .warning
            )
            return false
        }
    }

    /// 刷新终端安装情况和登录项授权状态。
    func refreshSystemState() {
        installedTerminals = terminalLauncher.installedTerminalKinds()
        launchAtLoginStatus = launchAtLoginController.status
    }

    /// 修改默认终端并立即持久化。
    func selectTerminal(_ terminal: TerminalKind) {
        settings.selectedTerminal = terminal
        statusMessage = "默认终端已切换为 \(terminal.displayName)"
    }

    /// 设置开机自启动，并在系统要求人工批准时给出明确提示。
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLoginStatus = launchAtLoginController.status

            if launchAtLoginStatus == .requiresApproval {
                statusMessage = "登录项等待系统批准"
                presentAlert(
                    title: "需要批准登录项",
                    message: "请在“系统设置 → 通用 → 登录项”中允许 Finder Terminal。",
                    style: .informational
                )
            } else {
                statusMessage = enabled ? "已开启开机自启动" : "已关闭开机自启动"
            }
        } catch {
            launchAtLoginStatus = launchAtLoginController.status
            let message = error.localizedDescription
            logger.error("修改登录项失败：\(message, privacy: .public)")
            presentAlert(
                title: "无法修改登录项",
                message: message,
                style: .warning
            )
        }
    }

    /// 打开系统登录项设置，供用户处理待批准状态。
    func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    /// 完成首次引导，保存登录项选择并关闭欢迎窗口。
    func completeOnboarding(launchAtLogin: Bool) {
        setLaunchAtLogin(launchAtLogin)
        settings.hasCompletedOnboarding = true
        onboardingWindowController?.close()
        onboardingWindowController = nil
    }

    /// 在首次启动时展示中文欢迎与权限引导窗口。
    func presentOnboardingIfNeeded() {
        guard !settings.hasCompletedOnboarding,
              onboardingWindowController == nil else {
            return
        }

        let view = OnboardingView(controller: self)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "欢迎使用 Finder Terminal"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 420))
        window.center()
        window.isReleasedWhenClosed = false

        let windowController = NSWindowController(window: window)
        onboardingWindowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 通过系统命令打开设置窗口，兼容仅支持旧接口的 macOS 13。
    func showLegacySettings() {
        let didOpenSettings = NSApp.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )

        if didOpenSettings {
            logger.info("已通过兼容接口打开设置窗口")
        } else {
            logger.error("兼容接口未能打开设置窗口")
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    /// 退出菜单栏应用。
    func quitApplication() {
        NSApp.terminate(nil)
    }

    /// 展示统一中文警告框，并确保用户能够看到错误。
    private func presentAlert(
        title: String,
        message: String,
        style: NSAlert.Style
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
