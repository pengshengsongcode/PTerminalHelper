import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var selectedTerminal: TerminalKind {
        didSet {
            defaults.set(selectedTerminal.rawValue, forKey: Keys.selectedTerminal)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    private enum Keys {
        static let selectedTerminal = "selectedTerminal"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    /// 从持久化配置中恢复用户选择，并为无效数据提供安全默认值。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawValue = defaults.string(forKey: Keys.selectedTerminal),
           let terminal = TerminalKind(rawValue: rawValue) {
            selectedTerminal = terminal
        } else {
            selectedTerminal = .terminal
        }

        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }
}
