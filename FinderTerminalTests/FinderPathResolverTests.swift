import Foundation
import XCTest
@testable import FinderTerminal

final class StaticFinderSnapshotProvider: FinderSnapshotProviding, @unchecked Sendable {
    private let value: Result<FinderPathSnapshot, Error>

    /// 保存固定 Finder 快照，供路径解析测试重复使用。
    init(value: Result<FinderPathSnapshot, Error>) {
        self.value = value
    }

    /// 返回预设快照或错误。
    func snapshot() async throws -> FinderPathSnapshot {
        try value.get()
    }
}

struct DictionaryMetadataProvider: FilePathMetadataProviding {
    let values: [String: FilePathMetadata]

    /// 按标准化路径返回测试元数据。
    func metadata(for url: URL) throws -> FilePathMetadata {
        values[url.standardizedFileURL.path]
            ?? FilePathMetadata(exists: false, isDirectory: false, isPackage: false)
    }
}

final class FinderPathResolverTests: XCTestCase {
    /// 验证选中文件夹时直接使用该文件夹。
    func testSelectedFolderUsesItself() async throws {
        let folderURL = URL(fileURLWithPath: "/tmp/项目 甲")
        let resolver = makeResolver(
            source: .selection,
            urls: [folderURL],
            metadata: [
                folderURL.path: .init(exists: true, isDirectory: true, isPackage: false)
            ]
        )

        let result = try await resolver.resolveDirectory()

        XCTAssertEqual(result.directoryURL.path, folderURL.standardizedFileURL.path)
        XCTAssertEqual(result.source, .selection)
        XCTAssertEqual(result.selectionCount, 1)
    }

    /// 验证选中文件时使用文件父目录。
    func testSelectedFileUsesParentDirectory() async throws {
        let folderURL = URL(fileURLWithPath: "/tmp/含 空格")
        let fileURL = folderURL.appendingPathComponent("含'引号.txt")
        let resolver = makeResolver(
            source: .selection,
            urls: [fileURL],
            metadata: [
                fileURL.path: .init(exists: true, isDirectory: false, isPackage: false),
                folderURL.path: .init(exists: true, isDirectory: true, isPackage: false)
            ]
        )

        let result = try await resolver.resolveDirectory()

        XCTAssertEqual(result.directoryURL.path, folderURL.standardizedFileURL.path)
    }

    /// 验证选中 App 文件包时使用文件包父目录。
    func testSelectedPackageUsesParentDirectory() async throws {
        let folderURL = URL(fileURLWithPath: "/Applications")
        let appURL = folderURL.appendingPathComponent("示例.app")
        let resolver = makeResolver(
            source: .selection,
            urls: [appURL],
            metadata: [
                appURL.path: .init(exists: true, isDirectory: true, isPackage: true),
                folderURL.path: .init(exists: true, isDirectory: true, isPackage: false)
            ]
        )

        let result = try await resolver.resolveDirectory()

        XCTAssertEqual(result.directoryURL.path, folderURL.standardizedFileURL.path)
    }

    /// 验证多选时只使用 Finder 返回的第一个项目。
    func testMultipleSelectionUsesFirstItem() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/第一个")
        let secondURL = URL(fileURLWithPath: "/tmp/第二个")
        let resolver = makeResolver(
            source: .selection,
            urls: [firstURL, secondURL],
            metadata: [
                firstURL.path: .init(exists: true, isDirectory: true, isPackage: false),
                secondURL.path: .init(exists: true, isDirectory: true, isPackage: false)
            ]
        )

        let result = try await resolver.resolveDirectory()

        XCTAssertEqual(result.directoryURL, firstURL.standardizedFileURL)
        XCTAssertEqual(result.selectionCount, 2)
    }

    /// 验证没有选择项目时使用 Finder 当前窗口目录。
    func testNoSelectionUsesWindowDirectory() async throws {
        let windowURL = URL(fileURLWithPath: "/tmp/当前窗口")
        let resolver = makeResolver(
            source: .window,
            urls: [windowURL],
            metadata: [
                windowURL.path: .init(exists: true, isDirectory: true, isPackage: false)
            ]
        )

        let result = try await resolver.resolveDirectory()

        XCTAssertEqual(result.directoryURL, windowURL.standardizedFileURL)
        XCTAssertEqual(result.selectionCount, 0)
    }

    /// 验证没有 Finder 窗口时使用桌面回退目录。
    func testNoWindowUsesFallbackDirectory() async throws {
        let desktopURL = URL(fileURLWithPath: "/Users/test/Desktop")
        let resolver = makeResolver(
            source: .fallback,
            urls: [desktopURL],
            metadata: [
                desktopURL.path: .init(exists: true, isDirectory: true, isPackage: false)
            ]
        )

        let result = try await resolver.resolveDirectory()

        XCTAssertEqual(result.directoryURL, desktopURL.standardizedFileURL)
        XCTAssertEqual(result.source, .fallback)
    }

    /// 验证目标路径失效时返回明确错误。
    func testMissingPathReturnsChineseError() async {
        let missingURL = URL(fileURLWithPath: "/tmp/已经删除")
        let resolver = makeResolver(
            source: .selection,
            urls: [missingURL],
            metadata: [:]
        )

        do {
            _ = try await resolver.resolveDirectory()
            XCTFail("路径失效时不应解析成功")
        } catch let error as FinderPathError {
            XCTAssertEqual(error, .pathDoesNotExist(missingURL.path))
            XCTAssertTrue(error.localizedDescription.contains("目标路径不存在"))
        } catch {
            XCTFail("返回了错误类型：\(error)")
        }
    }

    /// 构造注入固定快照和元数据的路径解析器。
    private func makeResolver(
        source: FinderPathSource,
        urls: [URL],
        metadata: [String: FilePathMetadata]
    ) -> DefaultFinderPathResolver {
        let snapshot = FinderPathSnapshot(source: source, urls: urls)
        return DefaultFinderPathResolver(
            snapshotProvider: StaticFinderSnapshotProvider(value: .success(snapshot)),
            metadataProvider: DictionaryMetadataProvider(values: metadata)
        )
    }
}
