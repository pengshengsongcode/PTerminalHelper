import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case notFound
    case unavailable

    var isRequestedEnabled: Bool {
        self == .enabled || self == .requiresApproval
    }
}

enum LaunchAtLoginAction: Equatable {
    case register
    case unregister
    case noChange
    case reportUnavailable
}

enum LaunchAtLoginPolicy {
    /// 根据系统状态和用户选择决定下一步登录项操作。
    static func action(
        enabled: Bool,
        status: LaunchAtLoginStatus
    ) -> LaunchAtLoginAction {
        if enabled {
            switch status {
            case .disabled, .notFound:
                return .register
            case .enabled, .requiresApproval:
                return .noChange
            case .unavailable:
                return .reportUnavailable
            }
        }

        switch status {
        case .enabled, .requiresApproval:
            return .unregister
        case .disabled, .notFound:
            return .noChange
        case .unavailable:
            return .reportUnavailable
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case serviceUnavailable

    var errorDescription: String? {
        "macOS 暂时无法访问登录项服务，请稍后重试。"
    }
}

@MainActor
protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }

    /// 修改 Finder Terminal 的开机自启动状态。
    func setEnabled(_ enabled: Bool) throws

    /// 打开系统“登录项”设置页面。
    func openSystemSettings()
}

@MainActor
final class DefaultLaunchAtLoginController: LaunchAtLoginManaging {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .unavailable
        }
    }

    /// 根据用户选择注册或注销主应用登录项。
    func setEnabled(_ enabled: Bool) throws {
        switch LaunchAtLoginPolicy.action(
            enabled: enabled,
            status: status
        ) {
        case .register:
            try service.register()
        case .unregister:
            try service.unregister()
        case .noChange:
            break
        case .reportUnavailable:
            throw LaunchAtLoginError.serviceUnavailable
        }
    }

    /// 跳转到系统设置，方便用户处理待批准的登录项。
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
