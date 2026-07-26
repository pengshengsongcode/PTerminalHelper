import AppKit
import CryptoKit
import Foundation
import os
import Security

struct SemanticVersion: Comparable, Sendable {
    private let components: [Int]

    /// 将 `v1.2.3` 或 `1.2.3` 转换成可比较的版本号。
    init?(_ rawValue: String) {
        let normalized = rawValue.hasPrefix("v")
            ? String(rawValue.dropFirst())
            : rawValue
        let parsedComponents = normalized.split(separator: ".").compactMap {
            Int($0)
        }

        guard !parsedComponents.isEmpty,
              parsedComponents.count == normalized.split(separator: ".").count else {
            return nil
        }

        components = parsedComponents
    }

    /// 忽略末尾补零差异比较两个版本是否相等。
    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let componentCount = max(
            lhs.components.count,
            rhs.components.count
        )
        return (0..<componentCount).allSatisfy { index in
            lhs.component(at: index) == rhs.component(at: index)
        }
    }

    /// 按数字分段比较版本大小，避免把 1.10 错判为小于 1.9。
    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let componentCount = max(
            lhs.components.count,
            rhs.components.count
        )

        for index in 0..<componentCount {
            let left = lhs.component(at: index)
            let right = rhs.component(at: index)
            if left != right {
                return left < right
            }
        }
        return false
    }

    /// 返回指定位置的版本分段，缺失位置按零处理。
    private func component(at index: Int) -> Int {
        guard components.indices.contains(index) else {
            return 0
        }
        return components[index]
    }
}

struct GitHubReleaseAsset: Decodable, Equatable, Sendable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

struct GitHubRelease: Decodable, Equatable, Sendable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

struct ReleaseUpdateCandidate: Equatable, Sendable {
    let version: String
    let releaseURL: URL
    let downloadURL: URL
    let digest: String
}

struct DownloadedUpdate: Equatable, Sendable {
    let version: String
    let releaseURL: URL
    let applicationURL: URL
}

enum ReleaseUpdatePolicy {
    static let applicationAssetName = "Finder.Terminal.zip"

    /// 从最新正式 Release 中筛选比当前版本更新的应用资产。
    static func candidate(
        release: GitHubRelease,
        currentVersion: String
    ) throws -> ReleaseUpdateCandidate? {
        guard let current = SemanticVersion(currentVersion) else {
            throw GitHubReleaseUpdateError.invalidCurrentVersion
        }
        guard let latest = SemanticVersion(release.tagName) else {
            throw GitHubReleaseUpdateError.invalidReleaseVersion
        }
        guard current < latest else {
            return nil
        }
        guard let asset = release.assets.first(where: {
            $0.name == applicationAssetName
        }) else {
            throw GitHubReleaseUpdateError.missingApplicationAsset
        }
        guard let digest = asset.digest,
              digest.hasPrefix("sha256:") else {
            throw GitHubReleaseUpdateError.missingDigest
        }

        return ReleaseUpdateCandidate(
            version: release.tagName,
            releaseURL: release.htmlURL,
            downloadURL: asset.browserDownloadURL,
            digest: digest
        )
    }

    /// 使用 GitHub 提供的 SHA-256 摘要校验下载内容。
    static func matchesDigest(_ data: Data, expectedDigest: String) -> Bool {
        let actualDigest = SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
        return expectedDigest.lowercased() == "sha256:\(actualDigest)"
    }
}

enum GitHubReleaseUpdateError: LocalizedError {
    case invalidCurrentVersion
    case invalidReleaseVersion
    case invalidResponse
    case requestFailed(String)
    case missingApplicationAsset
    case missingDigest
    case digestMismatch
    case extractionFailed(String)
    case invalidApplicationBundle
    case unexpectedBundleIdentifier
    case downloadedVersionMismatch
    case invalidCodeSignature(Int32)
    case applicationMustBeInApplications
    case installationFailed(String)
    case relaunchFailed(String)

    /// 返回可直接展示给用户的中文错误说明。
    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion:
            return "当前应用版本号无法识别。"
        case .invalidReleaseVersion:
            return "GitHub Release 版本号无法识别。"
        case .invalidResponse:
            return "GitHub 返回了无效的更新信息。"
        case let .requestFailed(message):
            return "检查更新失败：\(message)"
        case .missingApplicationAsset:
            return "最新 Release 中缺少 Finder.Terminal.zip。"
        case .missingDigest:
            return "最新 Release 缺少 SHA-256 校验值。"
        case .digestMismatch:
            return "更新包 SHA-256 校验失败，已停止安装。"
        case let .extractionFailed(message):
            return "解压更新包失败：\(message)"
        case .invalidApplicationBundle:
            return "更新包中没有有效的 Finder Terminal.app。"
        case .unexpectedBundleIdentifier:
            return "更新包的应用标识不匹配，已停止安装。"
        case .downloadedVersionMismatch:
            return "更新包版本与 GitHub Release 不一致。"
        case let .invalidCodeSignature(status):
            return "更新包代码签名校验失败，错误码：\(status)。"
        case .applicationMustBeInApplications:
            return "请先将 Finder Terminal.app 放入“应用程序”目录后再更新。"
        case let .installationFailed(message):
            return "安装更新失败：\(message)"
        case let .relaunchFailed(message):
            return "更新已安装，但重新打开失败：\(message)"
        }
    }
}

@MainActor
protocol ApplicationUpdating: AnyObject {
    /// 检查 GitHub 最新 Release，并在发现新版本时完成下载与校验。
    func checkAndDownload(currentVersion: String) async throws -> DownloadedUpdate?

    /// 用已经校验的应用替换当前安装版本。
    func install(_ update: DownloadedUpdate) throws -> URL

    /// 启动更新后的新实例并退出当前实例。
    func relaunchApplication(at applicationURL: URL) throws
}

@MainActor
final class GitHubReleaseUpdater: ApplicationUpdating {
    private static let repositoryBundleIdentifier =
        "com.pengshengsong.FinderTerminal"
    private static let latestReleaseURL =
        URL(
            string: "https://api.github.com/repos/pengshengsongcode/PTerminalHelper/releases/latest"
        ) ?? URL(fileURLWithPath: "/")

    private let session: URLSession
    private let fileManager: FileManager
    private let currentApplicationURL: URL
    private let endpoint: URL
    private let logger = Logger(
        subsystem: "com.pengshengsong.FinderTerminal",
        category: "应用更新"
    )

    /// 注入网络、文件系统和安装位置，便于独立验证更新策略。
    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        currentApplicationURL: URL = Bundle.main.bundleURL,
        endpoint: URL = GitHubReleaseUpdater.latestReleaseURL
    ) {
        self.session = session
        self.fileManager = fileManager
        self.currentApplicationURL = currentApplicationURL
        self.endpoint = endpoint
    }

    /// 请求 GitHub 最新 Release，发现更新后下载、校验并解压应用。
    func checkAndDownload(
        currentVersion: String
    ) async throws -> DownloadedUpdate? {
        logger.info("正在检查 GitHub 最新 Release")
        let releaseData = try await requestData(from: endpoint)
        let release: GitHubRelease

        do {
            release = try JSONDecoder().decode(
                GitHubRelease.self,
                from: releaseData
            )
        } catch {
            logger.error(
                "解析 GitHub Release 失败：\(error.localizedDescription, privacy: .public)"
            )
            throw GitHubReleaseUpdateError.invalidResponse
        }

        guard let candidate = try ReleaseUpdatePolicy.candidate(
            release: release,
            currentVersion: currentVersion
        ) else {
            logger.info("当前已经是最新版本")
            return nil
        }

        logger.info(
            "发现新版本 \(candidate.version, privacy: .public)，开始下载"
        )
        let archiveData = try await requestData(from: candidate.downloadURL)
        guard ReleaseUpdatePolicy.matchesDigest(
            archiveData,
            expectedDigest: candidate.digest
        ) else {
            logger.error("更新包 SHA-256 校验失败")
            throw GitHubReleaseUpdateError.digestMismatch
        }

        let applicationURL = try extractAndValidate(
            archiveData,
            version: candidate.version
        )
        logger.info(
            "新版本 \(candidate.version, privacy: .public) 已下载并通过校验"
        )
        return DownloadedUpdate(
            version: candidate.version,
            releaseURL: candidate.releaseURL,
            applicationURL: applicationURL
        )
    }

    /// 使用系统安全替换接口把新应用安装到当前应用位置。
    func install(_ update: DownloadedUpdate) throws -> URL {
        let destinationURL = currentApplicationURL.standardizedFileURL
        guard destinationURL.deletingLastPathComponent().path
                == "/Applications" else {
            throw GitHubReleaseUpdateError.applicationMustBeInApplications
        }

        do {
            let installedURL = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: update.applicationURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
            let resultURL = installedURL ?? destinationURL
            logger.info(
                "已安装 \(update.version, privacy: .public)：\(resultURL.path, privacy: .public)"
            )
            return resultURL
        } catch {
            logger.error(
                "安装更新失败：\(error.localizedDescription, privacy: .public)"
            )
            throw GitHubReleaseUpdateError.installationFailed(
                error.localizedDescription
            )
        }
    }

    /// 创建新应用实例，确认启动命令成功后退出旧实例。
    func relaunchApplication(at applicationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", applicationURL.path]

        do {
            try process.run()
            logger.info("已启动更新后的应用，准备退出当前实例")
            NSApp.terminate(nil)
        } catch {
            logger.error(
                "重新打开应用失败：\(error.localizedDescription, privacy: .public)"
            )
            throw GitHubReleaseUpdateError.relaunchFailed(
                error.localizedDescription
            )
        }
    }

    /// 请求 HTTPS 资源并校验 HTTP 成功状态。
    private func requestData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "2022-11-28",
            forHTTPHeaderField: "X-GitHub-Api-Version"
        )
        request.setValue(
            "Finder-Terminal-Updater",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                throw GitHubReleaseUpdateError.invalidResponse
            }
            return data
        } catch let error as GitHubReleaseUpdateError {
            throw error
        } catch {
            throw GitHubReleaseUpdateError.requestFailed(
                error.localizedDescription
            )
        }
    }

    /// 将下载包解压到目标磁盘的替换目录并验证应用身份。
    private func extractAndValidate(
        _ archiveData: Data,
        version: String
    ) throws -> URL {
        let replacementDirectory: URL
        do {
            replacementDirectory = try fileManager.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: currentApplicationURL,
                create: true
            )
        } catch {
            throw GitHubReleaseUpdateError.extractionFailed(
                error.localizedDescription
            )
        }

        let archiveURL = replacementDirectory.appendingPathComponent(
            ReleaseUpdatePolicy.applicationAssetName
        )
        let extractedDirectory = replacementDirectory.appendingPathComponent(
            "已解压更新",
            isDirectory: true
        )

        do {
            try archiveData.write(to: archiveURL, options: .atomic)
            try fileManager.createDirectory(
                at: extractedDirectory,
                withIntermediateDirectories: true
            )
            try runDitto(
                archiveURL: archiveURL,
                destinationURL: extractedDirectory
            )
        } catch let error as GitHubReleaseUpdateError {
            throw error
        } catch {
            throw GitHubReleaseUpdateError.extractionFailed(
                error.localizedDescription
            )
        }

        let applicationURL = extractedDirectory.appendingPathComponent(
            "Finder Terminal.app",
            isDirectory: true
        )
        try validateApplication(
            at: applicationURL,
            expectedVersion: version
        )
        return applicationURL
    }

    /// 使用系统 ditto 工具解压 Release ZIP，并保留应用资源属性。
    private func runDitto(
        archiveURL: URL,
        destinationURL: URL
    ) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-x",
            "-k",
            archiveURL.path,
            destinationURL.path
        ]
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GitHubReleaseUpdateError.extractionFailed(
                error.localizedDescription
            )
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)
                ?? "ditto 返回错误码 \(process.terminationStatus)"
            throw GitHubReleaseUpdateError.extractionFailed(message)
        }
    }

    /// 校验应用目录、Bundle ID、版本号和全部架构代码签名。
    private func validateApplication(
        at applicationURL: URL,
        expectedVersion: String
    ) throws {
        guard fileManager.fileExists(atPath: applicationURL.path),
              let bundle = Bundle(url: applicationURL) else {
            throw GitHubReleaseUpdateError.invalidApplicationBundle
        }
        guard bundle.bundleIdentifier
                == GitHubReleaseUpdater.repositoryBundleIdentifier else {
            throw GitHubReleaseUpdateError.unexpectedBundleIdentifier
        }

        let downloadedVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        guard let expectedSemanticVersion = SemanticVersion(expectedVersion),
              let downloadedVersion,
              let downloadedSemanticVersion = SemanticVersion(downloadedVersion),
              expectedSemanticVersion == downloadedSemanticVersion else {
            throw GitHubReleaseUpdateError.downloadedVersionMismatch
        }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            applicationURL as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess,
              let staticCode else {
            throw GitHubReleaseUpdateError.invalidCodeSignature(
                createStatus
            )
        }

        let flags = SecCSFlags(
            rawValue:
                kSecCSCheckAllArchitectures
                | kSecCSStrictValidate
                | kSecCSCheckNestedCode
        )
        let validityStatus = SecStaticCodeCheckValidity(
            staticCode,
            flags,
            nil
        )
        guard validityStatus == errSecSuccess else {
            throw GitHubReleaseUpdateError.invalidCodeSignature(
                validityStatus
            )
        }
    }
}
