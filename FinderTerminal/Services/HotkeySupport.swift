import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openFinderTerminal = Self(
        "openFinderTerminal",
        initial: .init(.t, modifiers: [.command, .shift])
    )
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
