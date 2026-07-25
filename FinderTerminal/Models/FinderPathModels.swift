import Foundation

enum FinderPathSource: String, Equatable, Sendable {
    case selection
    case window
    case fallback
}

struct FinderPathSnapshot: Equatable, Sendable {
    let source: FinderPathSource
    let urls: [URL]
}

struct FilePathMetadata: Equatable, Sendable {
    let exists: Bool
    let isDirectory: Bool
    let isPackage: Bool
}

struct FinderPathResolution: Equatable, Sendable {
    let directoryURL: URL
    let source: FinderPathSource
    let selectionCount: Int
}

enum FinderPathError: LocalizedError, Equatable {
    case automationDenied
    case finderUnavailable
    case invalidResponse
    case scriptFailed(String)
    case pathDoesNotExist(String)
    case pathIsNotDirectory(String)

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            return "没有读取 Finder 的权限。请前往“系统设置 → 隐私与安全性 → 自动化”，允许 Finder Terminal 控制 Finder。"
        case .finderUnavailable:
            return "无法连接 Finder，请确认 Finder 正在运行后重试。"
        case .invalidResponse:
            return "Finder 返回了无法识别的路径信息。"
        case let .scriptFailed(message):
            return "读取 Finder 路径失败：\(message)"
        case let .pathDoesNotExist(path):
            return "目标路径不存在：\(path)"
        case let .pathIsNotDirectory(path):
            return "无法确定可打开的目录：\(path)"
        }
    }
}
