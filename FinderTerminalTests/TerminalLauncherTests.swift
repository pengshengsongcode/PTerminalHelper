import Foundation
import XCTest
@testable import FinderTerminal

@MainActor
final class FakeTerminalWorkspace: TerminalWorkspaceProviding {
    var applications: [String: URL]
    var openedDirectories: [URL] = []
    var openedApplications: [URL] = []
    var openError: Error?

    /// 保存测试使用的已安装终端映射。
    init(applications: [String: URL]) {
        self.applications = applications
    }

    /// 返回测试映射中的应用地址。
    func applicationURL(bundleIdentifier: String) -> URL? {
        applications[bundleIdentifier]
    }

    /// 记录终端启动参数，或抛出预设错误。
    func openDirectory(_ directoryURL: URL, with applicationURL: URL) async throws {
        if let openError {
            throw openError
        }
        openedDirectories.append(directoryURL)
        openedApplications.append(applicationURL)
    }
}

final class TerminalLauncherTests: XCTestCase {
    /// 验证只展示已经安装的受支持终端。
    @MainActor
    func testInstalledTerminalKindsOnlyContainsAvailableApps() {
        let workspace = FakeTerminalWorkspace(
            applications: [
                TerminalKind.terminal.bundleIdentifier: URL(fileURLWithPath: "/Terminal.app"),
                TerminalKind.ghostty.bundleIdentifier: URL(fileURLWithPath: "/Ghostty.app")
            ]
        )
        let launcher = DefaultTerminalLauncher(workspace: workspace)

        XCTAssertEqual(launcher.installedTerminalKinds(), [.terminal, .ghostty])
    }

    /// 验证目标终端已安装时直接使用用户选择。
    @MainActor
    func testLaunchUsesRequestedTerminal() async throws {
        let iTermURL = URL(fileURLWithPath: "/iTerm.app")
        let workspace = FakeTerminalWorkspace(
            applications: [TerminalKind.iTerm2.bundleIdentifier: iTermURL]
        )
        let launcher = DefaultTerminalLauncher(workspace: workspace)
        let directoryURL = URL(fileURLWithPath: "/tmp/项目 '甲'")

        let result = try await launcher.openNewWindow(
            at: directoryURL,
            using: .iTerm2
        )

        XCTAssertEqual(result.launchedTerminal, .iTerm2)
        XCTAssertFalse(result.didFallback)
        XCTAssertEqual(workspace.openedDirectories, [directoryURL])
        XCTAssertEqual(workspace.openedApplications, [iTermURL])
    }

    /// 验证目标终端卸载后回退系统终端。
    @MainActor
    func testMissingRequestedTerminalFallsBackToSystemTerminal() async throws {
        let terminalURL = URL(fileURLWithPath: "/Terminal.app")
        let workspace = FakeTerminalWorkspace(
            applications: [TerminalKind.terminal.bundleIdentifier: terminalURL]
        )
        let launcher = DefaultTerminalLauncher(workspace: workspace)

        let result = try await launcher.openNewWindow(
            at: URL(fileURLWithPath: "/tmp"),
            using: .warp
        )

        XCTAssertEqual(result.launchedTerminal, .terminal)
        XCTAssertTrue(result.didFallback)
        XCTAssertEqual(workspace.openedApplications, [terminalURL])
    }

    /// 验证没有任何终端时返回明确错误。
    @MainActor
    func testNoInstalledTerminalReturnsError() async {
        let launcher = DefaultTerminalLauncher(
            workspace: FakeTerminalWorkspace(applications: [:])
        )

        do {
            _ = try await launcher.openNewWindow(
                at: URL(fileURLWithPath: "/tmp"),
                using: .warp
            )
            XCTFail("没有终端时不应启动成功")
        } catch let error as TerminalLaunchError {
            XCTAssertEqual(error, .noAvailableTerminal)
        } catch {
            XCTFail("返回了错误类型：\(error)")
        }
    }
}
