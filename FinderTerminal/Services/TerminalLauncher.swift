import AppKit
import Foundation
import os

struct TerminalLaunchResult: Equatable, Sendable {
    let requestedTerminal: TerminalKind
    let launchedTerminal: TerminalKind

    var didFallback: Bool {
        requestedTerminal != launchedTerminal
    }
}

enum TerminalLaunchError: LocalizedError, Equatable {
    case noAvailableTerminal
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAvailableTerminal:
            return "没有找到可用的终端应用，请确认系统“终端”已安装。"
        case let .openFailed(message):
            return "打开终端失败：\(message)"
        }
    }
}

@MainActor
protocol TerminalWorkspaceProviding: AnyObject {
    /// 根据 Bundle ID 查找本机已安装的应用。
    func applicationURL(bundleIdentifier: String) -> URL?

    /// 将目录 URL 交给指定终端应用并激活应用。
    func openDirectory(_ directoryURL: URL, with applicationURL: URL) async throws
}

@MainActor
protocol TerminalLaunching: AnyObject {
    /// 返回当前机器已安装且受支持的终端列表。
    func installedTerminalKinds() -> [TerminalKind]

    /// 在指定终端中打开目录；目标终端缺失时回退系统终端。
    func openNewWindow(
        at directoryURL: URL,
        using requestedTerminal: TerminalKind
    ) async throws -> TerminalLaunchResult
}

@MainActor
final class NSWorkspaceTerminalAdapter: TerminalWorkspaceProviding {
    /// 使用 Launch Services 查找应用位置。
    func applicationURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    /// 通过打开 public.directory 文档请求终端创建目录窗口。
    func openDirectory(_ directoryURL: URL, with applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.open(
                [directoryURL],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

@MainActor
final class DefaultTerminalLauncher: TerminalLaunching {
    private let workspace: any TerminalWorkspaceProviding
    private let logger = Logger(
        subsystem: "com.pengshengsong.FinderTerminal",
        category: "终端启动"
    )

    /// 注入工作区适配器，便于模拟终端安装和启动结果。
    init(workspace: any TerminalWorkspaceProviding = NSWorkspaceTerminalAdapter()) {
        self.workspace = workspace
    }

    /// 按产品约定顺序返回当前已安装终端。
    func installedTerminalKinds() -> [TerminalKind] {
        TerminalKind.allCases.filter { terminal in
            workspace.applicationURL(bundleIdentifier: terminal.bundleIdentifier) != nil
        }
    }

    /// 优先启动用户选择的终端，缺失时安全回退系统终端。
    func openNewWindow(
        at directoryURL: URL,
        using requestedTerminal: TerminalKind
    ) async throws -> TerminalLaunchResult {
        let launchedTerminal: TerminalKind
        let applicationURL: URL

        if let requestedURL = workspace.applicationURL(
            bundleIdentifier: requestedTerminal.bundleIdentifier
        ) {
            launchedTerminal = requestedTerminal
            applicationURL = requestedURL
        } else if let terminalURL = workspace.applicationURL(
            bundleIdentifier: TerminalKind.terminal.bundleIdentifier
        ) {
            launchedTerminal = .terminal
            applicationURL = terminalURL
            logger.notice(
                "所选终端未安装，已回退系统终端：\(requestedTerminal.displayName, privacy: .public)"
            )
        } else {
            logger.error("没有找到任何可用终端")
            throw TerminalLaunchError.noAvailableTerminal
        }

        do {
            try await workspace.openDirectory(
                directoryURL,
                with: applicationURL
            )
            logger.info(
                "已使用 \(launchedTerminal.displayName, privacy: .public) 打开目录：\(directoryURL.path, privacy: .public)"
            )
        } catch {
            logger.error("打开终端失败：\(error.localizedDescription, privacy: .public)")
            throw TerminalLaunchError.openFailed(error.localizedDescription)
        }

        return TerminalLaunchResult(
            requestedTerminal: requestedTerminal,
            launchedTerminal: launchedTerminal
        )
    }
}
