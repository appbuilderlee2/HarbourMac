import Foundation
import Darwin
import HarbourCore

final class StreamCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var overflow = false
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        let room = max(0, 8_000_000 - buffer.count)
        if data.count > room { overflow = true }
        buffer.append(data.prefix(room))
    }
    func result() -> (Data, Bool) { lock.lock(); defer { lock.unlock() }; return (buffer, overflow) }
}

@MainActor final class Runner: ObservableObject {
    @Published var busy = false
    @Published var log = ""
    @Published var outcome = "尚未執行"
    @Published var taskTitle = ""
    @Published var taskPhase = ""
    @Published var startedAt: Date?
    @Published var elapsedSeconds = 0
    var onEvent: ((BridgeEvent) -> Void)?
    var onLine: ((String) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var timer: Timer?
    private var progressTimer: Timer?
    private var stopped = false
    private var runID = UUID()
    var resourceURL: URL { Bundle.module.resourceURL!.appendingPathComponent("Resources") }
    var engineURL: URL { resourceURL.appendingPathComponent("Engine") }
    var workerURL: URL { Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("HarbourWorker") }

    func send(_ response: String) {
        guard busy, let input = input else { return }
        do { try input.write(contentsOf: Data(response.utf8)) }
        catch { stop(); outcome = "回覆失敗：\(error.localizedDescription)" }
    }
    func stop() {
        guard let process = process, process.isRunning else { return }
        stopped = true
        try? input?.close(); input = nil
        let pid = process.processIdentifier
        // The worker creates a group with its own PID before invoking the CLI.
        if kill(-pid, SIGTERM) != 0 { process.terminate() }
        let id = runID
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, self.runID == id, process.isRunning else { return }
            kill(-pid, SIGKILL)
        }
    }
    func start(_ executable: URL, _ arguments: [String], environment extras: [String: String] = [:], timeout: TimeInterval = 1800, completion: ((Data, Int32) -> Void)? = nil) {
        guard !busy else { return }
        guard FileManager.default.isExecutableFile(atPath: workerURL.path) else { outcome = "缺少 HarbourWorker；請用 build.command 完整打包 App。"; completion?(Data(), 127); return }
        busy = true; stopped = false; log = ""; outcome = "執行中"; startedAt = Date(); elapsedSeconds = 0; taskPhase = "正在準備…"
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, self.busy else { return }
            self.elapsedSeconds += 1
        }
        runID = UUID()
        let token = UUID().uuidString
        let process = Process(), stdout = Pipe(), stderr = Pipe(), stdinPipe = Pipe()
        process.executableURL = workerURL
        process.arguments = [executable.path] + arguments
        // Whitelist environment. Never inherit user-provided test/delete switches.
        var env = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                   "USER": NSUserName(), "LOGNAME": NSUserName(), "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "dumb", "LANG": "en_US.UTF-8", "HARBOUR_TOKEN": token]
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] { env["TMPDIR"] = tmp }
        extras.forEach { env[$0.key] = $0.value }
        process.environment = env
        process.standardOutput = stdout; process.standardError = stderr; process.standardInput = stdinPipe
        let capture = StreamCapture(), drains = DispatchGroup()
        func drain(_ handle: FileHandle, isOutput: Bool) {
            drains.enter()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                defer { drains.leave(); try? handle.close() }
                var pending = Data()
                while true {
                    guard let data = try? handle.read(upToCount: 16384), !data.isEmpty else { break }
                    if isOutput { capture.append(data) }
                    pending.append(data)
                    while let index = pending.firstIndex(of: 10) {
                        let line = String(decoding: pending.prefix(upTo: index), as: UTF8.self)
                        pending.removeSubrange(...index)
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            if isOutput, let event = BridgeEvent.parse(line, token: token) { self.onEvent?(event) }
                            else {
                                if isOutput { self.onLine?(line) }
                                self.appendLog(TextFormat.plain(line) + "\n")
                            }
                        }
                    }
                    if pending.count > 2_000_000 { pending.removeAll() }
                }
                if !pending.isEmpty {
                    let tail = String(decoding: pending, as: UTF8.self)
                    DispatchQueue.main.async { [weak self] in self?.appendLog(TextFormat.plain(tail)) }
                }
            }
        }
        process.terminationHandler = { [weak self] task in
            let drainOK = drains.wait(timeout: .now() + 5) == .success
            let result = capture.result()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.timer?.invalidate(); self.timer = nil; self.progressTimer?.invalidate(); self.progressTimer = nil
                try? self.input?.close(); self.input = nil; self.process = nil; self.busy = false
                self.startedAt = nil
                let rc: Int32 = self.stopped ? 130 : ((!drainOK || result.1) ? 74 : task.terminationStatus)
                self.outcome = rc == 0 ? "操作結束；請查看結果中的略過或失敗項目" : (rc == 130 ? "已停止／取消；已完成的操作不會自動復原" : "操作未完整完成（\(rc)），請查看詳細結果")
                completion?(result.0, rc)
            }
        }
        drain(stdout.fileHandleForReading, isOutput: true)
        drain(stderr.fileHandleForReading, isOutput: false)
        do {
            try process.run()
            self.process = process; input = stdinPipe.fileHandleForWriting
            if timeout > 0 {
                timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.stop() }
                }
            }
        } catch {
            try? stdout.fileHandleForWriting.close(); try? stderr.fileHandleForWriting.close()
            progressTimer?.invalidate(); progressTimer = nil; startedAt = nil
            try? stdinPipe.fileHandleForWriting.close()
            busy = false; outcome = error.localizedDescription
            completion?(Data(), 127)
        }
    }
    private func appendLog(_ text: String) {
        log += text
        if log.utf8.count > 1_000_000 { log = String(log.suffix(700_000)) }
    }
}
