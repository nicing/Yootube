import AppKit
import CFNetwork
import Foundation

@MainActor
final class LocalServiceManager: ObservableObject {
    static let shared = LocalServiceManager()

    enum State: Equatable {
        case idle
        case starting(String)
        case ready
        case failed(String)
    }

    nonisolated static let invidiousURL = URL(string: "http://127.0.0.1:38473")!

    @Published private(set) var state: State = .idle

    private var startupTask: Task<Void, Never>?
    private var postgresProcess: Process?
    private var companionProcess: Process?
    private var invidiousProcess: Process?
    private var utilityProcess: Process?
    private var logHandles: [FileHandle] = []

    var dataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Yootube", isDirectory: true)
    }

    func start() {
        guard startupTask == nil, state != .ready else { return }

        startupTask = Task {
            do {
                try await startServices()
                state = .ready
            } catch {
                stopProcesses()
                state = Task.isCancelled ? .idle : .failed(error.localizedDescription)
            }
            startupTask = nil
        }
    }

    func restart() {
        stop()
        state = .idle
        start()
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
        stopProcesses()
    }

    func revealDataDirectory() {
        try? FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([dataDirectory])
    }

    func revealLogsDirectory() {
        let directory = dataDirectory.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private func startServices() async throws {
        let runtime = try RuntimeLayout.locate()
        let fileManager = FileManager.default
        let postgresData = dataDirectory.appendingPathComponent("Postgres", isDirectory: true)
        let socketDirectory = dataDirectory.appendingPathComponent("Sockets", isDirectory: true)
        let logsDirectory = dataDirectory.appendingPathComponent("Logs", isDirectory: true)

        for directory in [dataDirectory, socketDirectory, logsDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: dataDirectory.path
        )

        if await endpointResponds(
            URL(string: "http://127.0.0.1:38473/api/v1/stats")!,
            requireSuccess: true
        ) {
            throw ServiceError.portInUse(38473)
        }
        if await endpointResponds(
            URL(string: "http://127.0.0.1:38475/")!,
            requireSuccess: false
        ) {
            throw ServiceError.portInUse(38475)
        }

        let secrets = try loadOrCreateSecrets()
        let outboundProxy = detectSystemProxy()

        if !fileManager.fileExists(atPath: postgresData.appendingPathComponent("PG_VERSION").path) {
            state = .starting(L10n.t("正在初始化本地数据库…"))
            try await runAndWait(
                executable: runtime.postgres.appendingPathComponent("bin/initdb"),
                arguments: [
                    "-D", postgresData.path,
                    "-U", "yootube",
                    "--auth=trust",
                    "--encoding=UTF8",
                    "--no-instructions"
                ],
                logURL: logsDirectory.appendingPathComponent("setup.log")
            )
        }

        state = .starting(L10n.t("正在启动 PostgreSQL…"))
        postgresProcess = try launch(
            executable: runtime.postgres.appendingPathComponent("bin/postgres"),
            arguments: [
                "-D", postgresData.path,
                "-p", "38474",
                "-h", "127.0.0.1",
                "-k", socketDirectory.path
            ],
            logURL: logsDirectory.appendingPathComponent("postgres.log")
        )
        try await waitForPostgres(runtime: runtime, logURL: logsDirectory.appendingPathComponent("setup.log"))
        try await ensureDatabase(runtime: runtime, logURL: logsDirectory.appendingPathComponent("setup.log"))

        state = .starting(L10n.t("正在启动视频代理…"))
        companionProcess = try launch(
            executable: runtime.companion,
            environment: [
                "PORT": "38475",
                "HOST": "127.0.0.1",
                "SERVER_SECRET_KEY": secrets.companion
            ].merging(outboundProxy.map { ["PROXY": $0.url] } ?? [:]) { _, new in new },
            logURL: logsDirectory.appendingPathComponent("companion.log")
        )
        try await waitForEndpoint(
            URL(string: "http://127.0.0.1:38475/healthz")!,
            requireSuccess: true,
            process: companionProcess,
            serviceName: L10n.t("视频代理")
        )
        state = .starting(L10n.t("正在准备视频播放…"))
        try await waitForCompanionToken(key: secrets.companion, process: companionProcess)

        let configURL = dataDirectory.appendingPathComponent("config.yml")
        try invidiousConfiguration(secrets: secrets, outboundProxy: outboundProxy).write(
            to: configURL,
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configURL.path
        )

        state = .starting(L10n.t("正在启动 Invidious…"))
        invidiousProcess = try launch(
            executable: runtime.invidious.appendingPathComponent("invidious"),
            environment: ["INVIDIOUS_CONFIG_FILE": configURL.path],
            currentDirectory: runtime.invidious,
            logURL: logsDirectory.appendingPathComponent("invidious.log")
        )
        try await waitForEndpoint(
            URL(string: "http://127.0.0.1:38473/api/v1/stats")!,
            requireSuccess: true,
            process: invidiousProcess,
            serviceName: "Invidious"
        )
    }

    private func ensureDatabase(runtime: RuntimeLayout, logURL: URL) async throws {
        let marker = dataDirectory.appendingPathComponent("database-ready")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }

        let result = try await runAndCapture(
            executable: runtime.postgres.appendingPathComponent("bin/psql"),
            arguments: [
                "-h", "127.0.0.1",
                "-p", "38474",
                "-U", "yootube",
                "-d", "postgres",
                "-tAc", "SELECT 1 FROM pg_database WHERE datname='invidious'"
            ],
            logURL: logURL
        )

        if result.trimmingCharacters(in: .whitespacesAndNewlines) != "1" {
            try await runAndWait(
                executable: runtime.postgres.appendingPathComponent("bin/createdb"),
                arguments: [
                    "-h", "127.0.0.1",
                    "-p", "38474",
                    "-U", "yootube",
                    "invidious"
                ],
                logURL: logURL
            )
        }

        try Data().write(to: marker, options: .atomic)
    }

    private func waitForPostgres(runtime: RuntimeLayout, logURL: URL) async throws {
        for _ in 0..<60 {
            try Task.checkCancellation()
            guard postgresProcess?.isRunning == true else {
                throw ServiceError.processExited("PostgreSQL")
            }
            do {
                try await runAndWait(
                    executable: runtime.postgres.appendingPathComponent("bin/pg_isready"),
                    arguments: ["-h", "127.0.0.1", "-p", "38474", "-U", "yootube"],
                    logURL: logURL
                )
                return
            } catch {
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        throw ServiceError.startupTimedOut("PostgreSQL")
    }

    private func waitForEndpoint(
        _ url: URL,
        requireSuccess: Bool,
        process: Process?,
        serviceName: String,
        attempts: Int = 120,
        interval: Duration = .milliseconds(250),
        requestTimeout: TimeInterval = 1
    ) async throws {
        for _ in 0..<attempts {
            try Task.checkCancellation()
            guard let process, process.isRunning else {
                throw ServiceError.processExited(serviceName)
            }
            if await endpointResponds(url, requireSuccess: requireSuccess, timeout: requestTimeout) {
                return
            }
            try await Task.sleep(for: interval)
        }
        throw ServiceError.startupTimedOut(serviceName)
    }

    private func waitForCompanionToken(key: String, process: Process?) async throws {
        for _ in 0..<360 {
            try Task.checkCancellation()
            guard let process, process.isRunning else {
                throw ServiceError.processExited(L10n.t("视频代理"))
            }
            if await companionTokenIsReady(key: key) { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw ServiceError.startupTimedOut(L10n.t("视频代理"))
    }

    private func companionTokenIsReady(key: String) async -> Bool {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:38475/companion/youtubei/v1/player")!
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"videoId":"invalid"}"#.utf8)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            // The invalid ID reaches validation only after the PO token exists.
            return (response as? HTTPURLResponse)?.statusCode == 400
        } catch {
            return false
        }
    }

    private func endpointResponds(
        _ url: URL,
        requireSuccess: Bool,
        timeout: TimeInterval = 1
    ) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return requireSuccess ? (200..<300).contains(httpResponse.statusCode) : true
        } catch {
            return false
        }
    }

    private func loadOrCreateSecrets() throws -> (companion: String, hmac: String) {
        let secretURL = dataDirectory.appendingPathComponent("secrets.txt")
        if let text = try? String(contentsOf: secretURL, encoding: .utf8) {
            let values = text.split(separator: "\n").map(String.init)
            if values.count == 2, values[0].count == 16, !values[1].isEmpty {
                return (values[0], values[1])
            }
        }

        let companion = randomAlphanumeric(length: 16)
        let hmac = randomAlphanumeric(length: 48)
        try "\(companion)\n\(hmac)\n".write(to: secretURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: secretURL.path
        )
        return (companion, hmac)
    }

    private func randomAlphanumeric(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    private func invidiousConfiguration(
        secrets: (companion: String, hmac: String),
        outboundProxy: OutboundProxy?
    ) -> String {
        """
        db:
          user: yootube
          password: ""
          host: 127.0.0.1
          port: 38474
          dbname: invidious
        check_tables: true
        port: 38473
        host_binding: 127.0.0.1
        domain: 127.0.0.1
        external_port: 38473
        https_only: false
        hmac_key: "\(secrets.hmac)"
        invidious_companion:
          - private_url: "http://127.0.0.1:38475/companion"
        invidious_companion_key: "\(secrets.companion)"
        statistics_enabled: false
        use_pubsub_feeds: false
        default_user_preferences:
          locale: zh-CN
          dark_mode: dark
        \(outboundProxy?.yaml ?? "")
        """
    }

    private func detectSystemProxy() -> OutboundProxy? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let candidates: [(enabled: CFString, host: CFString, port: CFString, type: String)] = [
            (kCFNetworkProxiesHTTPSEnable, kCFNetworkProxiesHTTPSProxy, kCFNetworkProxiesHTTPSPort, "http"),
            (kCFNetworkProxiesHTTPEnable, kCFNetworkProxiesHTTPProxy, kCFNetworkProxiesHTTPPort, "http"),
            (kCFNetworkProxiesSOCKSEnable, kCFNetworkProxiesSOCKSProxy, kCFNetworkProxiesSOCKSPort, "socks5")
        ]

        for candidate in candidates {
            let enabled = (settings[candidate.enabled as String] as? NSNumber)?.boolValue == true
            guard enabled,
                  let host = settings[candidate.host as String] as? String,
                  !host.isEmpty,
                  let port = settings[candidate.port as String] as? NSNumber else {
                continue
            }
            return OutboundProxy(type: candidate.type, host: host, port: port.intValue)
        }
        return nil
    }

    private func launch(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        currentDirectory: URL? = nil,
        logURL: URL
    ) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.currentDirectoryURL = currentDirectory

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        logHandles.append(logHandle)
        return process
    }

    private func runAndWait(
        executable: URL,
        arguments: [String],
        logURL: URL
    ) async throws {
        _ = try await runProcess(
            executable: executable,
            arguments: arguments,
            logURL: logURL,
            captureOutput: false
        )
    }

    private func runAndCapture(
        executable: URL,
        arguments: [String],
        logURL: URL
    ) async throws -> String {
        try await runProcess(
            executable: executable,
            arguments: arguments,
            logURL: logURL,
            captureOutput: true
        )
    }

    private func runProcess(
        executable: URL,
        arguments: [String],
        logURL: URL,
        captureOutput: Bool
    ) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        utilityProcess = process

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finishedProcess in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                if !output.isEmpty {
                    if !FileManager.default.fileExists(atPath: logURL.path) {
                        FileManager.default.createFile(atPath: logURL.path, contents: nil)
                    }
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: Data(output.utf8))
                        try? handle.close()
                    }
                }

                if finishedProcess.terminationStatus == 0 {
                    continuation.resume(returning: captureOutput ? output : "")
                } else {
                    continuation.resume(throwing: ServiceError.processFailed(
                        executable.lastPathComponent,
                        output
                    ))
                }
                Task { @MainActor [weak self] in
                    if self?.utilityProcess === finishedProcess {
                        self?.utilityProcess = nil
                    }
                }
            }

            do {
                try process.run()
            } catch {
                utilityProcess = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func stopProcesses() {
        stopProcess(utilityProcess, timeout: 1)
        stopProcess(invidiousProcess, timeout: 3)
        stopProcess(companionProcess, timeout: 3)
        stopProcess(postgresProcess, timeout: 5)
        utilityProcess = nil
        invidiousProcess = nil
        companionProcess = nil
        postgresProcess = nil
        logHandles.forEach { try? $0.close() }
        logHandles.removeAll()
    }

    private func stopProcess(_ process: Process?, timeout: TimeInterval) {
        guard let process, process.isRunning else { return }

        process.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }
}

private struct OutboundProxy {
    let type: String
    let host: String
    let port: Int

    var url: String {
        "\(type)://\(host):\(port)"
    }

    var yaml: String {
        let escapedHost = host.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        http_proxy:
          type: \(type)
          host: "\(escapedHost)"
          port: \(port)
        """
    }
}

private struct RuntimeLayout {
    let root: URL
    let postgres: URL
    let companion: URL
    let invidious: URL

    static func locate() throws -> RuntimeLayout {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Runtime", isDirectory: true))
        }
#if DEBUG
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/runtime-cache/prepared", isDirectory: true)
        )
#endif

        for root in candidates {
            let layout = RuntimeLayout(
                root: root,
                postgres: root.appendingPathComponent("postgres", isDirectory: true),
                companion: root.appendingPathComponent("companion/invidious_companion"),
                invidious: root.appendingPathComponent("invidious", isDirectory: true)
            )
            if FileManager.default.isExecutableFile(atPath: layout.companion.path),
               FileManager.default.isExecutableFile(
                atPath: layout.invidious.appendingPathComponent("invidious").path
               ),
               FileManager.default.isExecutableFile(
                atPath: layout.postgres.appendingPathComponent("bin/postgres").path
               ) {
                return layout
            }
        }
        throw ServiceError.runtimeMissing
    }
}

private enum ServiceError: LocalizedError {
    case runtimeMissing
    case portInUse(Int)
    case processExited(String)
    case startupTimedOut(String)
    case processFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            return L10n.t("本地 Invidious 运行组件不完整，请重新安装 Yootube。")
        case let .portInUse(port):
            return L10n.t("本地端口 \(port) 已被其他进程占用。请关闭占用该端口的程序后重试。")
        case let .processExited(service):
            return L10n.t("\(service) 启动后立即退出。请查看设置中的日志目录。")
        case let .startupTimedOut(service):
            return L10n.t("\(service) 启动超时。请查看设置中的日志目录。")
        case let .processFailed(process, output):
            let detail = output.split(separator: "\n").suffix(3).joined(separator: " ")
            return L10n.t("\(process) 启动失败：\(detail)")
        }
    }
}
