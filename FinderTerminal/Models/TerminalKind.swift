import Foundation

enum TerminalKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case terminal
    case iTerm2
    case warp
    case ghostty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal:
            return "终端"
        case .iTerm2:
            return "iTerm2"
        case .warp:
            return "Warp"
        case .ghostty:
            return "Ghostty"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal:
            return "com.apple.Terminal"
        case .iTerm2:
            return "com.googlecode.iterm2"
        case .warp:
            return "dev.warp.Warp-Stable"
        case .ghostty:
            return "com.mitchellh.ghostty"
        }
    }
}
