import Foundation
import XCTest
@testable import FinderTerminal

final class GitHubReleaseUpdaterTests: XCTestCase {
    /// 验证版本比较按数字分段处理双位数版本。
    func testSemanticVersionUsesNumericComparison() throws {
        let older = try XCTUnwrap(SemanticVersion("v1.9.0"))
        let newer = try XCTUnwrap(SemanticVersion("1.10.0"))

        XCTAssertLessThan(older, newer)
        XCTAssertEqual(
            try XCTUnwrap(SemanticVersion("1.0")),
            try XCTUnwrap(SemanticVersion("1.0.0"))
        )
    }

    /// 验证发现新版本时选择名称精确匹配的应用资产。
    func testUpdateCandidateSelectsApplicationAsset() throws {
        let releaseURL = try XCTUnwrap(
            URL(string: "https://github.com/example/releases/tag/v1.1.0")
        )
        let downloadURL = try XCTUnwrap(
            URL(string: "https://github.com/example/Finder.Terminal.zip")
        )
        let release = GitHubRelease(
            tagName: "v1.1.0",
            htmlURL: releaseURL,
            assets: [
                GitHubReleaseAsset(
                    name: "Finder.Terminal.zip",
                    browserDownloadURL: downloadURL,
                    digest: "sha256:abc"
                )
            ]
        )

        let candidate = try ReleaseUpdatePolicy.candidate(
            release: release,
            currentVersion: "1.0.4"
        )

        XCTAssertEqual(candidate?.version, "v1.1.0")
        XCTAssertEqual(candidate?.downloadURL, downloadURL)
        XCTAssertEqual(candidate?.releaseURL, releaseURL)
    }

    /// 验证当前版本不低于 Release 时不会重复下载。
    func testCurrentVersionDoesNotDownloadAgain() throws {
        let releaseURL = try XCTUnwrap(
            URL(string: "https://github.com/example/releases/tag/v1.1.0")
        )
        let release = GitHubRelease(
            tagName: "v1.1.0",
            htmlURL: releaseURL,
            assets: []
        )

        XCTAssertNil(
            try ReleaseUpdatePolicy.candidate(
                release: release,
                currentVersion: "1.1.0"
            )
        )
    }

    /// 验证下载内容必须与 GitHub 提供的 SHA-256 完全一致。
    func testReleaseDigestValidation() {
        let data = Data("finder terminal".utf8)
        let digest =
            "sha256:64e81c57f05194252f5478cc38b6dd6ceec434f8b05be954b6006b2c7126c581"

        XCTAssertTrue(
            ReleaseUpdatePolicy.matchesDigest(
                data,
                expectedDigest: digest
            )
        )
        XCTAssertFalse(
            ReleaseUpdatePolicy.matchesDigest(
                data,
                expectedDigest: "sha256:0000"
            )
        )
    }
}
