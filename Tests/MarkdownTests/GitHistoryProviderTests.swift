import XCTest

final class GitHistoryProviderTests: XCTestCase {

    // MARK: - parseHistory

    func testParseHistoryReadsFieldsAndPath() {
        let output = "\u{1e}abc123\u{1f}abc1\u{1f}Alice\u{1f}2026-01-01T10:00:00Z\u{1f}first commit\n\nfile.md\n"
        let entries = GitHistoryProvider.parseHistory(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "abc123")
        XCTAssertEqual(entries[0].shortHash, "abc1")
        XCTAssertEqual(entries[0].author, "Alice")
        XCTAssertEqual(entries[0].date, "2026-01-01T10:00:00Z")
        XCTAssertEqual(entries[0].subject, "first commit")
        XCTAssertEqual(entries[0].path, "file.md")
        XCTAssertEqual(entries[0].kind, "commit")
    }

    func testParseHistoryHandlesMultipleCommits() {
        let output = [
            "\u{1e}aaa\u{1f}a\u{1f}Alice\u{1f}2026-01-02T10:00:00Z\u{1f}second\n\nfile.md\n",
            "\u{1e}bbb\u{1f}b\u{1f}Bob\u{1f}2026-01-01T10:00:00Z\u{1f}first\n\nold.md\n",
        ].joined()
        let entries = GitHistoryProvider.parseHistory(output)
        XCTAssertEqual(entries.map { $0.id }, ["aaa", "bbb"])
        XCTAssertEqual(entries.map { $0.path }, ["file.md", "old.md"])
    }

    func testParseHistoryIgnoresChunksWithoutFields() {
        XCTAssertTrue(GitHistoryProvider.parseHistory("\n\nnothing here\n").isEmpty)
    }

    // MARK: - parseParentPath

    func testParseParentPathForRename() {
        XCTAssertEqual(GitHistoryProvider.parseParentPath("R100\told.md\tnew.md\n", for: "new.md"), "old.md")
    }

    func testParseParentPathForModify() {
        XCTAssertEqual(GitHistoryProvider.parseParentPath("M\tfile.md\n", for: "file.md"), "file.md")
    }

    func testParseParentPathFallsBackToTheGivenPath() {
        XCTAssertEqual(GitHistoryProvider.parseParentPath("", for: "file.md"), "file.md")
        XCTAssertEqual(GitHistoryProvider.parseParentPath("A\tother.md\n", for: "file.md"), "file.md")
    }

    // MARK: - relativePath

    func testRelativePathInsideRoot() {
        let root = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
        let file = URL(fileURLWithPath: "/tmp/repo/docs/a.md")
        XCTAssertEqual(GitHistoryProvider.relativePath(fileURL: file, root: root), "docs/a.md")
    }

    func testRelativePathOutsideRoot() {
        let root = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
        let file = URL(fileURLWithPath: "/tmp/other/a.md")
        XCTAssertNil(GitHistoryProvider.relativePath(fileURL: file, root: root))
    }

    // MARK: - safe environment

    func testSafeEnvironmentDisablesPromptingAndReadsNoUserConfig() {
        let env = GitProcessRunner.safeEnvironment(home: "/tmp/home")
        XCTAssertEqual(env["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertEqual(env["GIT_OPTIONAL_LOCKS"], "0")
        XCTAssertEqual(env["GIT_CONFIG_NOSYSTEM"], "1")
        XCTAssertEqual(env["LC_ALL"], "C")
        XCTAssertEqual(env["HOME"], "/tmp/home")
    }

    func testRunnerStopsACommandThatExceedsTheTimeout() throws {
        let runner = GitProcessRunner(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            timeout: 0.3
        )
        XCTAssertThrowsError(try runner.run(["5"], in: URL(fileURLWithPath: NSTemporaryDirectory()))) { error in
            XCTAssertEqual(error as? GitHistoryError, .timeout)
        }
    }

    // MARK: - Integration with a real repository

    func testRepositoryDetectionAndHistory() throws {
        let repo = try makeRepository()
        let provider = GitHistoryProvider(fileURL: repo.appendingPathComponent("readme.md"))

        let root = try provider.repositoryRoot()
        XCTAssertEqual(
            root.resolvingSymlinksInPath().path,
            repo.resolvingSymlinksInPath().path
        )

        let entries = try provider.history()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].subject, "second commit")
        XCTAssertEqual(entries[0].kind, "commit")
        XCTAssertEqual(entries[0].path, "readme.md")
    }

    func testHistoryIsLimitedToTenCommits() throws {
        let repo = try makeRepository()
        let file = repo.appendingPathComponent("readme.md")
        let runner = GitProcessRunner()
        for index in 3...13 {
            try "line \(index)\n".write(to: file, atomically: true, encoding: .utf8)
            _ = try runner.run(["add", "readme.md"], in: repo)
            _ = try runner.run(["commit", "-q", "-m", "commit \(index)"], in: repo)
        }

        let provider = GitHistoryProvider(fileURL: file)
        XCTAssertEqual(try provider.history().count, GitHistoryProvider.historyLimit)
    }

    func testUncommittedEntryAppearsAndDisappears() throws {
        let repo = try makeRepository()
        let file = repo.appendingPathComponent("readme.md")
        let provider = GitHistoryProvider(fileURL: file)

        XCTAssertNil(try provider.uncommittedEntry())

        try "# Title\n\nhello brave new world\n".write(to: file, atomically: true, encoding: .utf8)
        let entry = try provider.uncommittedEntry()
        XCTAssertEqual(entry?.id, "working")
        XCTAssertEqual(entry?.kind, "working")
        XCTAssertEqual(entry?.path, "readme.md")
    }

    func testUntrackedFileHasNoUncommittedEntryAndNoHistory() throws {
        let repo = try makeRepository()
        let file = repo.appendingPathComponent("untracked.md")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)
        let provider = GitHistoryProvider(fileURL: file)

        XCTAssertNil(try provider.uncommittedEntry())
        XCTAssertTrue(try provider.history().isEmpty)
    }

    func testContentAndParentContent() throws {
        let repo = try makeRepository()
        let provider = GitHistoryProvider(fileURL: repo.appendingPathComponent("readme.md"))
        let entries = try provider.history()
        let latest = try XCTUnwrap(entries.first)

        let content = try provider.content(hash: latest.id, path: latest.path)
        XCTAssertTrue(content.contains("brave"))

        let parent = try provider.parentContent(hash: latest.id, path: latest.path)
        XCTAssertTrue(parent.contains("hello world"))
        XCTAssertFalse(parent.contains("brave"))

        let rootCommit = try XCTUnwrap(entries.last)
        XCTAssertEqual(try provider.parentContent(hash: rootCommit.id, path: rootCommit.path), "")
    }

    func testHeadContent() throws {
        let repo = try makeRepository()
        let file = repo.appendingPathComponent("readme.md")
        try "# Title\n\nhello brave new world\n".write(to: file, atomically: true, encoding: .utf8)
        let provider = GitHistoryProvider(fileURL: file)
        let head = try provider.headContent()
        XCTAssertTrue(head.contains("brave"))
        XCTAssertFalse(head.contains("new world"))
    }

    func testPayloadForNonRepository() throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("a.md")
        try "hi\n".write(to: file, atomically: true, encoding: .utf8)

        let payload = GitHistoryProvider(fileURL: file).payload()
        XCTAssertEqual(payload["available"] as? Bool, false)
        XCTAssertEqual(payload["reason"] as? String, "not-a-repository")
    }

    func testPayloadForRepository() throws {
        let repo = try makeRepository()
        let payload = GitHistoryProvider(fileURL: repo.appendingPathComponent("readme.md")).payload()
        XCTAssertEqual(payload["available"] as? Bool, true)
        let entries = payload["entries"] as? [[String: Any]]
        XCTAssertEqual(entries?.count, 2)
        XCTAssertEqual(entries?.first?["subject"] as? String, "second commit")
    }

    // MARK: - Fixtures

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("git-history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        let runner = GitProcessRunner()
        _ = try runner.run(["init", "-q"], in: directory)
        _ = try runner.run(["config", "user.email", "tests@example.com"], in: directory)
        _ = try runner.run(["config", "user.name", "Tests"], in: directory)

        let file = directory.appendingPathComponent("readme.md")
        try "# Title\n\nhello world\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try runner.run(["add", "readme.md"], in: directory)
        _ = try runner.run(["commit", "-q", "-m", "first commit"], in: directory)

        try "# Title\n\nhello brave world\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try runner.run(["add", "readme.md"], in: directory)
        _ = try runner.run(["commit", "-q", "-m", "second commit"], in: directory)

        return directory
    }
}
