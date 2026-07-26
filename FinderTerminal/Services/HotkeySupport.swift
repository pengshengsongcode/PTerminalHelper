import AppKit
import KeyboardShortcuts
import os

extension KeyboardShortcuts.Name {
    static let openFinderTerminal = Self(
        "openFinderTerminal",
        initial: FinderTerminalShortcut.recommended
    )
}

enum FinderTerminalShortcut {
    static let recommended = KeyboardShortcuts.Shortcut(
        .t,
        modifiers: [.control, .option]
    )
    static let legacyDefault = KeyboardShortcuts.Shortcut(
        .t,
        modifiers: [.command, .shift]
    )
    static let displayText = "⌃⌥T"

    private static let migrationVersion = 1
    private static let migrationVersionKey = "shortcutMigrationVersion"
    private static let logger = Logger(
        subsystem: "com.pengshengsong.FinderTerminal",
        category: "快捷键迁移"
    )

    /// 判断是否应把旧版默认快捷键迁移为不与 Finder 冲突的新快捷键。
    static func shouldMigrate(
        currentShortcut: KeyboardShortcuts.Shortcut?,
        completedVersion: Int
    ) -> Bool {
        completedVersion < migrationVersion
            && currentShortcut == legacyDefault
    }

    /// 首次升级到新版时迁移旧默认快捷键，并保留用户自定义的其他快捷键。
    @MainActor
    @discardableResult
    static func migrateLegacyDefaultIfNeeded(
        defaults: UserDefaults = .standard
    ) -> Bool {
        let completedVersion = defaults.integer(
            forKey: migrationVersionKey
        )
        let currentShortcut = KeyboardShortcuts.getShortcut(
            for: .openFinderTerminal
        )
        let needsMigration = shouldMigrate(
            currentShortcut: currentShortcut,
            completedVersion: completedVersion
        )

        if needsMigration {
            KeyboardShortcuts.setShortcut(
                recommended,
                for: .openFinderTerminal
            )
            logger.info("已将旧版默认快捷键迁移为 ⌃⌥T")
        }

        defaults.set(
            migrationVersion,
            forKey: migrationVersionKey
        )
        return needsMigration
    }
}

enum ShortcutPolicy {
    static let finderBundleIdentifier = "com.apple.finder"

    /// 仅当 Finder 是前台应用时允许处理全局快捷键。
    static func shouldHandle(frontmostBundleIdentifier: String?) -> Bool {
        frontmostBundleIdentifier == finderBundleIdentifier
    }
}

@MainActor
protocol FrontmostApplicationProviding: AnyObject {
    /// 返回当前接收键盘事件的前台应用 Bundle ID。
    func bundleIdentifier() -> String?
}

@MainActor
final class NSWorkspaceFrontmostApplicationProvider: FrontmostApplicationProviding {
    /// 使用 NSWorkspace 查询前台应用。
    func bundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
