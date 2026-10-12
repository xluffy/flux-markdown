import Foundation

/// A single entry in the Git history panel.
struct GitHistoryEntry: Equatable {
    let id: String
    let shortHash: String
    let author: String
    let date: String
    let subject: String
    let kind: String
    let path: String

    var dictionary: [String: Any] {
        [
            "id": id,
            "shortHash": shortHash,
            "author": author,
            "date": date,
            "subject": subject,
            "kind": kind,
            "path": path,
        ]
    }
}

enum GitHistoryError: Error, Equatable {
    case notARepository
    case accessDenied
    case commandFailed
    case timeout
}

struct GitProcessResult: Equatable {
    let status: Int32
    let stdout: String
    let stderr: String
}

protocol GitRunning {
    func run(_ arguments: [String], in directory: URL) throws -> GitProcessResult
}

/// Runs `/usr/bin/git` with a safe environment and a timeout.
struct GitProcessRunner: GitRunning {
    let executableURL: URL
    let timeout: TimeInterval
    let environment: [String: String]

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        timeout: TimeInterval = 3.0,
        environment: [String: String]? = nil
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        self.environment = environment ?? GitProcessRunner.safeEnvironment()
    }

    /// Build an environment that never prompts and never reads the user config.
    static func safeEnvironment(home: String = NSTemporaryDirectory()) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GIT_PAGER"] = "cat"
        env["LC_ALL"] = "C"
        env["HOME"] = home
        return env
    }

    func run(_ arguments: [String], in directory: URL) throws -> GitProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw GitHistoryError.commandFailed
        }

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            group.wait()
            throw GitHistoryError.timeout
        }
        process.waitUntilExit()
        group.wait()

        return GitProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}

/// Read the Git history and the revisions of one Markdown file.
struct GitHistoryProvider {
    static let historyLimit = 10

    let fileURL: URL
    let runner: GitRunning

    init(fileURL: URL, runner: GitRunning = GitProcessRunner()) {
        self.fileURL = fileURL
        self.runner = runner
    }

    // MARK: - Pure helpers

    /// The path of `fileURL` relative to `root`, or `nil` when `fileURL` is outside.
    static func relativePath(fileURL: URL, root: URL) -> String? {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let filePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }

    /// Parse the output of `git log --format=<us> --name-only`.
    static func parseHistory(_ output: String) -> [GitHistoryEntry] {
        var entries: [GitHistoryEntry] = []
        for chunk in output.components(separatedBy: "\u{1e}") {
            let lines = chunk.components(separatedBy: "\n")
            guard let fieldLine = lines.first(where: { $0.contains("\u{1f}") }) else { continue }
            let fields = fieldLine.components(separatedBy: "\u{1f}")
            guard fields.count >= 5 else { continue }

            let paths = lines.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.contains("\u{1f}")
            }
            let path = paths.last?.trimmingCharacters(in: .whitespaces) ?? ""
            entries.append(
                GitHistoryEntry(
                    id: fields[0],
                    shortHash: fields[1],
                    author: fields[2],
                    date: fields[3],
                    subject: fields[4],
                    kind: "commit",
                    path: path
                )
            )
        }
        return entries
    }

    /// Read the parent path from `git show --name-status -M` output.
    /// A rename line is `R100<TAB>old<TAB>new`. The parent path is the old path.
    static func parseParentPath(_ output: String, for path: String) -> String {
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count >= 2 else { continue }
            if parts.count >= 3 {
                let newPath = parts[parts.count - 1]
                if newPath == path {
                    return parts[parts.count - 2]
                }
            } else if parts[1] == path {
                return parts[1]
            }
        }
        return path
    }

    // MARK: - Repository

    func repositoryRoot() throws -> URL {
        let start = fileURL.deletingLastPathComponent()
        let result = try runner.run(["rev-parse", "--show-toplevel"], in: start)
        guard result.status == 0 else {
            let stderr = result.stderr.lowercased()
            if stderr.contains("not a git repository") {
                throw GitHistoryError.notARepository
            }
            throw GitHistoryError.accessDenied
        }
        let top = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !top.isEmpty else { throw GitHistoryError.notARepository }

        let root = URL(fileURLWithPath: top, isDirectory: true)
        // A linked worktree or a submodule uses a `.git` file. The spec excludes it.
        var isDirectory: ObjCBool = false
        let gitPath = root.appendingPathComponent(".git", isDirectory: true)
        if FileManager.default.fileExists(atPath: gitPath.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            throw GitHistoryError.notARepository
        }
        return root
    }

    private func relativePath(in root: URL) throws -> String {
        guard let relative = GitHistoryProvider.relativePath(fileURL: fileURL, root: root) else {
            throw GitHistoryError.notARepository
        }
        return relative
    }

    // MARK: - History

    func history() throws -> [GitHistoryEntry] {
        let root = try repositoryRoot()
        let relative = try relativePath(in: root)
        let format = "%x1e%H%x1f%h%x1f%an%x1f%aI%x1f%s"
        let result = try runner.run(
            ["log", "-n", String(GitHistoryProvider.historyLimit), "--follow", "--name-only", "--format=\(format)", "--", relative],
            in: root
        )
        guard result.status == 0 else { throw GitHistoryError.commandFailed }
        return GitHistoryProvider.parseHistory(result.stdout)
    }

    func uncommittedEntry() throws -> GitHistoryEntry? {
        let root = try repositoryRoot()
        let relative = try relativePath(in: root)
        let result = try runner.run(["status", "--porcelain", "--", relative], in: root)
        guard result.status == 0 else { return nil }

        let porcelain = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if porcelain.isEmpty { return nil }
        if porcelain.hasPrefix("??") { return nil } // untracked file: no history
        return GitHistoryEntry(
            id: "working",
            shortHash: "working",
            author: "",
            date: "",
            subject: "Uncommitted changes",
            kind: "working",
            path: relative
        )
    }

    // MARK: - Revisions

    func currentContent() throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }

    func revisedContent(_ spec: String) throws -> String {
        let root = try repositoryRoot()
        let result = try runner.run(["show", spec], in: root)
        guard result.status == 0 else { throw GitHistoryError.commandFailed }
        return result.stdout
    }

    func content(hash: String, path: String) throws -> String {
        try revisedContent("\(hash):\(path)")
    }

    func headContent() throws -> String {
        let root = try repositoryRoot()
        let relative = try relativePath(in: root)
        return try revisedContent("HEAD:\(relative)")
    }

    func parentContent(hash: String, path: String) throws -> String {
        let root = try repositoryRoot()
        let parentPath = GitHistoryProvider.parseParentPath(
            (try? runner.run(["show", "--name-status", "-M", "--format=", hash], in: root))?.stdout ?? "",
            for: path
        )
        let result = try runner.run(["show", "\(hash)^:\(parentPath)"], in: root)
        if result.status != 0 { return "" } // root commit: empty baseline
        return result.stdout
    }

    // MARK: - Payload

    func payload() -> [String: Any] {
        do {
            let root = try repositoryRoot()
            var entries = try history()
            if let working = try uncommittedEntry() {
                entries.insert(working, at: 0)
            }
            return [
                "available": true,
                "repositoryRoot": root.path,
                "entries": entries.map { $0.dictionary },
            ]
        } catch GitHistoryError.notARepository {
            return ["available": false, "reason": "not-a-repository", "entries": []]
        } catch GitHistoryError.accessDenied {
            return ["available": false, "reason": "no-access", "entries": []]
        } catch {
            return ["available": false, "reason": "command-failed", "entries": []]
        }
    }
}
