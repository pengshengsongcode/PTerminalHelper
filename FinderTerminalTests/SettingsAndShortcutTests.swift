import Foundation
import XCTest
@testable import FinderTerminal

final class SettingsAndShortcutTests: XCTestCase {
    /// 验证用户选择的终端能够写入并恢复。
    @MainActor
    func testSelectedTerminalPersists() throws {
        let suiteName = "FinderTerminalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let firstSettings = AppSettings(defaults: defaults)
        firstSettings.selectedTerminal = .ghostty

        let restoredSettings = AppSettings(defaults: defaults)
        XCTAssertEqual(restoredSettings.selectedTerminal, .ghostty)
    }

    /// 验证损坏的终端配置会安全回退系统终端。
    @MainActor
    func testInvalidTerminalSettingUsesSystemTerminal() throws {
        let suiteName = "FinderTerminalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set("不存在的终端", forKey: "selectedTerminal")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.selectedTerminal, .terminal)
    }

    /// 验证快捷键只允许 Finder 前台状态。
    func testShortcutPolicyOnlyAllowsFinder() {
        XCTAssertTrue(
            ShortcutPolicy.shouldHandle(
                frontmostBundleIdentifier: "com.apple.finder"
            )
        )
        XCTAssertFalse(
            ShortcutPolicy.shouldHandle(
                frontmostBundleIdentifier: "com.apple.Terminal"
            )
        )
        XCTAssertFalse(
            ShortcutPolicy.shouldHandle(frontmostBundleIdentifier: nil)
        )
    }

    /// 验证旧版默认快捷键会在首次升级时迁移。
    func testLegacyDefaultShortcutRequiresMigration() {
        XCTAssertTrue(
            FinderTerminalShortcut.shouldMigrate(
                currentShortcut: FinderTerminalShortcut.legacyDefault,
                completedVersion: 0
            )
        )
    }

    /// 验证用户自定义快捷键不会被升级逻辑覆盖。
    func testCustomShortcutDoesNotRequireMigration() {
        XCTAssertFalse(
            FinderTerminalShortcut.shouldMigrate(
                currentShortcut: FinderTerminalShortcut.recommended,
                completedVersion: 0
            )
        )
    }

    /// 验证已完成迁移后不会重复修改快捷键。
    func testCompletedShortcutMigrationDoesNotRepeat() {
        XCTAssertFalse(
            FinderTerminalShortcut.shouldMigrate(
                currentShortcut: FinderTerminalShortcut.legacyDefault,
                completedVersion: 1
            )
        )
    }

    /// 验证等待系统批准的登录项仍保持开关开启状态。
    func testLaunchAtLoginApprovalStateRemainsEnabled() {
        XCTAssertTrue(LaunchAtLoginStatus.enabled.isRequestedEnabled)
        XCTAssertTrue(LaunchAtLoginStatus.requiresApproval.isRequestedEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.disabled.isRequestedEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.unavailable.isRequestedEnabled)
    }
}
