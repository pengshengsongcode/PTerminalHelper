import AppKit
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

    /// 验证 Finder 位于前台时读取 Finder 当前目录。
    func testShortcutPolicyUsesFinderDirectoryWhenFinderIsFrontmost() {
        XCTAssertEqual(
            ShortcutPolicy.action(
                frontmostBundleIdentifier: "com.apple.finder"
            ),
            .finderDirectory
        )
    }

    /// 验证 Finder 不在前台时快捷键直接回退桌面目录。
    func testShortcutPolicyUsesDesktopWhenFinderIsNotFrontmost() {
        XCTAssertEqual(
            ShortcutPolicy.action(
                frontmostBundleIdentifier: "com.apple.Terminal"
            ),
            .desktopDirectory
        )
    }

    /// 验证系统无法返回前台应用时仍安全回退桌面目录。
    func testShortcutPolicyUsesDesktopWithoutFrontmostApplication() {
        XCTAssertEqual(
            ShortcutPolicy.action(
                frontmostBundleIdentifier: nil
            ),
            .desktopDirectory
        )
    }

    /// 验证设置窗口策略使用跨空间浮动层级。
    @MainActor
    func testSettingsWindowUsesFloatingLevel() {
        XCTAssertEqual(
            SettingsWindowPresentationPolicy.level,
            .floating
        )
        XCTAssertTrue(
            SettingsWindowPresentationPolicy.collectionBehavior
                .contains(.canJoinAllSpaces)
        )
        XCTAssertTrue(
            SettingsWindowPresentationPolicy.collectionBehavior
                .contains(.fullScreenAuxiliary)
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
        XCTAssertFalse(LaunchAtLoginStatus.notFound.isRequestedEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.unavailable.isRequestedEnabled)
    }

    /// 验证系统首次返回未找到时仍会执行注册，避免开关点击无效。
    func testLaunchAtLoginNotFoundStateRegisters() {
        XCTAssertEqual(
            LaunchAtLoginPolicy.action(
                enabled: true,
                status: .notFound
            ),
            .register
        )
    }

    /// 验证已开启或待批准状态能够执行注销。
    func testLaunchAtLoginEnabledStateUnregisters() {
        XCTAssertEqual(
            LaunchAtLoginPolicy.action(
                enabled: false,
                status: .enabled
            ),
            .unregister
        )
        XCTAssertEqual(
            LaunchAtLoginPolicy.action(
                enabled: false,
                status: .requiresApproval
            ),
            .unregister
        )
    }
}
