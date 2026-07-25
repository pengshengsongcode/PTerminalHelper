import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var isRequestedEnabled: Bool {
        self == .enabled || self == .requiresApproval
    }
}

@MainActor
protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }

    /// 修改 Finder Terminal 的登录时启动状态。
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
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    /// 根据用户选择注册或注销主应用登录项。
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if service.status == .notRegistered {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }

    /// 跳转到系统设置，方便用户处理待批准的登录项。
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
