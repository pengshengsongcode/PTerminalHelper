import Foundation
import os

protocol FinderSnapshotProviding: Sendable {
    /// 读取 Finder 当前选择、窗口目录或桌面回退目录。
    func snapshot() async throws -> FinderPathSnapshot
}

protocol FilePathMetadataProviding: Sendable {
    /// 获取路径存在性、目录类型和文件包类型。
    func metadata(for url: URL) throws -> FilePathMetadata
}

protocol FinderPathResolving: Sendable {
    /// 根据 Finder 状态解析最终需要打开的目录。
    func resolveDirectory() async throws -> FinderPathResolution
}

struct URLFilePathMetadataProvider: FilePathMetadataProviding {
    /// 使用文件系统和 URL 资源属性读取路径元数据。
    func metadata(for url: URL) throws -> FilePathMetadata {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        )

        guard exists else {
            return FilePathMetadata(
                exists: false,
                isDirectory: false,
                isPackage: false
            )
        }

        let values = try url.resourceValues(forKeys: [.isPackageKey])
        return FilePathMetadata(
            exists: true,
            isDirectory: isDirectory.boolValue,
            isPackage: values.isPackage ?? false
        )
    }
}

final class AppleScriptFinderSnapshotProvider: FinderSnapshotProviding, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pengshengsong.FinderTerminal.finder-script")
    private let logger = Logger(
        subsystem: "com.pengshengsong.FinderTerminal",
        category: "Finder路径"
    )

    private let scriptSource = """
    tell application "Finder"
        set selectedPaths to {}
        repeat with selectedItem in selection
            try
                set end of selectedPaths to POSIX path of (selectedItem as alias)
            end try
        end repeat

        if (count of selectedPaths) > 0 then
            return {"selection", selectedPaths}
        end if

        if (count of Finder windows) > 0 then
            set targetPath to POSIX path of (target of front Finder window as alias)
            return {"window", {targetPath}}
        end if

        try
            set fallbackPath to POSIX path of (insertion location as alias)
        on error
            set fallbackPath to POSIX path of (desktop as alias)
        end try
        return {"fallback", {fallbackPath}}
    end tell
    """

    /// 在独立串行队列执行 AppleScript，避免阻塞 SwiftUI 主线程。
    func snapshot() async throws -> FinderPathSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let snapshot = try executeScript()
                    continuation.resume(returning: snapshot)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 执行 Finder 脚本并将 Apple Event 描述符转换成路径快照。
    private func executeScript() throws -> FinderPathSnapshot {
        guard let script = NSAppleScript(source: scriptSource) else {
            logger.error("创建 Finder AppleScript 失败")
            throw FinderPathError.finderUnavailable
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            throw mapScriptError(errorInfo)
        }

        guard result.numberOfItems >= 2,
              let sourceText = result.atIndex(1)?.stringValue,
              let source = FinderPathSource(rawValue: sourceText),
              let pathsDescriptor = result.atIndex(2) else {
            logger.error("Finder 返回的数据结构无效")
            throw FinderPathError.invalidResponse
        }

        let urls = parseURLs(from: pathsDescriptor)
        guard !urls.isEmpty else {
            logger.error("Finder 没有返回可用路径")
            throw FinderPathError.invalidResponse
        }

        logger.debug("已读取 Finder 路径，来源：\(source.rawValue, privacy: .public)")
        return FinderPathSnapshot(source: source, urls: urls)
    }

    /// 从 Apple Event 列表中提取所有有效的 POSIX 路径。
    private func parseURLs(from descriptor: NSAppleEventDescriptor) -> [URL] {
        let itemCount = descriptor.numberOfItems
        guard itemCount > 0 else {
            return []
        }

        return (1...itemCount).compactMap { index in
            guard let path = descriptor.atIndex(index)?.stringValue,
                  !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path).standardizedFileURL
        }
    }

    /// 将 AppleScript 错误映射为用户可理解的中文错误。
    private func mapScriptError(_ errorInfo: NSDictionary) -> FinderPathError {
        let number = errorInfo["NSAppleScriptErrorNumber"] as? Int
        let message = (errorInfo["NSAppleScriptErrorMessage"] as? String)
            ?? "未知 AppleScript 错误"

        if number == -1743 {
            logger.error("读取 Finder 被系统拒绝，请检查自动化权限")
            return .automationDenied
        }

        if number == -600 {
            logger.error("Finder 当前不可用")
            return .finderUnavailable
        }

        logger.error("读取 Finder 失败：\(message, privacy: .public)")
        return .scriptFailed(message)
    }
}

struct DefaultFinderPathResolver: FinderPathResolving {
    private let snapshotProvider: any FinderSnapshotProviding
    private let metadataProvider: any FilePathMetadataProviding

    /// 注入 Finder 快照和文件元数据提供者，便于独立测试路径规则。
    init(
        snapshotProvider: any FinderSnapshotProviding = AppleScriptFinderSnapshotProvider(),
        metadataProvider: any FilePathMetadataProviding = URLFilePathMetadataProvider()
    ) {
        self.snapshotProvider = snapshotProvider
        self.metadataProvider = metadataProvider
    }

    /// 按“文件夹取自身、文件或文件包取父目录”的规则解析路径。
    func resolveDirectory() async throws -> FinderPathResolution {
        let snapshot = try await snapshotProvider.snapshot()
        guard let firstURL = snapshot.urls.first else {
            throw FinderPathError.invalidResponse
        }

        let sourceMetadata = try metadataProvider.metadata(for: firstURL)
        guard sourceMetadata.exists else {
            throw FinderPathError.pathDoesNotExist(firstURL.path)
        }

        let directoryURL: URL
        if snapshot.source == .selection,
           (!sourceMetadata.isDirectory || sourceMetadata.isPackage) {
            directoryURL = firstURL.deletingLastPathComponent().standardizedFileURL
        } else {
            directoryURL = firstURL.standardizedFileURL
        }

        let directoryMetadata = try metadataProvider.metadata(for: directoryURL)
        guard directoryMetadata.exists else {
            throw FinderPathError.pathDoesNotExist(directoryURL.path)
        }
        guard directoryMetadata.isDirectory else {
            throw FinderPathError.pathIsNotDirectory(directoryURL.path)
        }

        return FinderPathResolution(
            directoryURL: directoryURL,
            source: snapshot.source,
            selectionCount: snapshot.source == .selection ? snapshot.urls.count : 0
        )
    }
}
