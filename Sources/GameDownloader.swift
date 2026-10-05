import Foundation
import CryptoKit

@MainActor
final class GameDownloader: ObservableObject {
    static let shared = GameDownloader()

    static let manifestURL = URL(string: "https://bo3-mac.s3.us-east-1.amazonaws.com/manifest.json")!
    static let cacheDir: String = {
        FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Caches/bo3-download"
    }()

    private static let pipeStreamBufferSize = 4 * 1024 * 1024 // 4 MB

    // MARK: - Types

    enum Phase: Equatable {
        case idle
        case fetchingManifest
        case downloading
        case paused
        case decompressing
        case finished
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.fetchingManifest, .fetchingManifest),
                 (.downloading, .downloading), (.paused, .paused),
                 (.decompressing, .decompressing), (.finished, .finished):
                return true
            case let (.failed(a), .failed(b)):
                return a == b
            default:
                return false
            }
        }

        var isFailed: Bool { if case .failed = self { return true }; return false }
        var isPaused: Bool { if case .paused = self { return true }; return false }
        var isDownloading: Bool { if case .downloading = self { return true }; return false }
    }

    struct Manifest: Codable {
        let version: String
        let game: String
        let sourceSize: Int64
        let chunkSize: Int64
        let totalChunks: Int
        let compression: String
        let chunks: [ChunkInfo]
    }

    struct ChunkInfo: Codable {
        let index: Int
        let file: String
        let size: Int64
        let sha256: String
        let url: String
    }

    // MARK: - Published State

    @Published var phase: Phase = .idle
    @Published var totalBytes: Int64 = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var completedChunkCount: Int = 0
    @Published var totalChunkCount: Int = 0
    @Published var activeChunkProgress: [Int: Double] = [:]
    @Published var downloadSpeed: Double = 0
    @Published var concurrentSlots: Int = 5
    @Published var decompressedChunkCount: Int = 0

    // MARK: - Internal State

    private var manifest: Manifest?
    private var mainTask: Task<Void, Never>?
    private var activeDownloads: [Int: ActiveDownload] = [:]
    private var completedIndices: Set<Int> = []
    private var pendingQueue: [ChunkInfo] = []
    private var downloadContinuation: CheckedContinuation<Void, Error>?
    private var _isPaused = false
    private(set) var destinationDir: String = ""
    private var speedTracker = SpeedTracker()

    private struct ActiveDownload {
        let session: URLSession
        let task: URLSessionDownloadTask
        let delegate: ChunkDownloadDelegate
    }

    var overallProgress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }

    var statusText: String {
        switch phase {
        case .idle:
            return "Ready to download"
        case .fetchingManifest:
            return "Connecting to server..."
        case .downloading:
            let active = activeChunkProgress.count
            if active > 1 {
                return "Downloading \(active) chunks (\(completedChunkCount)/\(totalChunkCount) complete)"
            }
            if totalChunkCount > 0 {
                return "Downloading chunk \(completedChunkCount + 1) of \(totalChunkCount)"
            }
            return "Downloading..."
        case .paused:
            return "Paused — \(completedChunkCount)/\(totalChunkCount) chunks complete"
        case .decompressing:
            return "Extracting game files… (\(GameDownloader.shared.decompressedChunkCount)/\(GameDownloader.shared.totalChunkCount) chunks fed)"
        case .finished:
            return "Installation complete!"
        case let .failed(msg):
            return "Error: \(msg)"
        }
    }

    var speedText: String {
        guard downloadSpeed > 0 else { return "" }
        let mbps = downloadSpeed / 1_048_576
        if mbps >= 1 {
            return String(format: "%.1f MB/s", mbps)
        }
        let kbps = downloadSpeed / 1024
        return String(format: "%.0f KB/s", kbps)
    }

    // MARK: - Public API

    func startDownload(to parentDir: String, concurrency: Int = 5) {
        guard phase == .idle || phase.isFailed else { return }

        _isPaused = false
        destinationDir = parentDir
        concurrentSlots = max(concurrency, 1)
        completedIndices = loadCompletedIndices()
        downloadedBytes = 0
        totalBytes = 0
        activeChunkProgress = [:]
        speedTracker = SpeedTracker()

        mainTask = Task { await runPipeline() }
    }

    func setConcurrency(_ newValue: Int) {
        let clamped = max(newValue, 1)
        concurrentSlots = clamped
        if phase.isDownloading {
            fillDownloadSlots()
        }
    }

    func pause() {
        guard phase.isDownloading else { return }
        _isPaused = true

        for (idx, download) in activeDownloads {
            download.session.invalidateAndCancel()
            let chunkPath = Self.chunkPath(for: idx)
            try? FileManager.default.removeItem(atPath: chunkPath)
        }
        activeDownloads.removeAll()
        activeChunkProgress.removeAll()
        pendingQueue.removeAll()
        downloadSpeed = 0

        saveCompletedIndices()

        downloadContinuation?.resume()
        downloadContinuation = nil

        phase = .paused
    }

    func resume() {
        guard phase.isPaused else { return }
        _isPaused = false

        mainTask = Task { await runPipeline() }
    }

    func cancel() {
        _isPaused = false
        for (_, download) in activeDownloads {
            download.session.invalidateAndCancel()
        }
        activeDownloads.removeAll()
        mainTask?.cancel()
        mainTask = nil
        downloadContinuation?.resume(throwing: CancellationError())
        downloadContinuation = nil

        try? FileManager.default.removeItem(atPath: Self.cacheDir)
        clearCompletedIndices()

        phase = .idle
        downloadedBytes = 0
        totalBytes = 0
        completedChunkCount = 0
        totalChunkCount = 0
        activeChunkProgress = [:]
        completedIndices = []
        downloadSpeed = 0
    }

    // MARK: - Pipeline

    private func runPipeline() async {
        do {
            if manifest == nil {
                phase = .fetchingManifest
                manifest = try await fetchManifest()
            }
            guard let manifest else { throw DownloadError.manifestFetchFailed }

            totalChunkCount = manifest.totalChunks
            totalBytes = manifest.chunks.reduce(0) { $0 + $1.size }

            let priorBytes = manifest.chunks
                .filter { completedIndices.contains($0.index) }
                .reduce(0 as Int64) { $0 + $1.size }
            downloadedBytes = priorBytes
            completedChunkCount = completedIndices.count

            try FileManager.default.createDirectory(
                atPath: Self.cacheDir, withIntermediateDirectories: true
            )

            phase = .downloading

            let pending = manifest.chunks
                .filter { !completedIndices.contains($0.index) }
                .sorted { $0.index < $1.index }

            if !pending.isEmpty {
                try await downloadChunksPhase(pending)
            }

            if _isPaused { return }
            if Task.isCancelled { return }

            decompressedChunkCount = 0
            phase = .decompressing
            try await decompressAllChunks(manifest: manifest)

            try? FileManager.default.removeItem(atPath: Self.cacheDir)
            clearCompletedIndices()

            Paths.setCustomPath(destinationDir + "/Call of Duty Black Ops III")

            phase = .finished
        } catch is CancellationError {
            if !_isPaused { phase = .idle }
        } catch {
            if !_isPaused {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Download Phase

    private func downloadChunksPhase(_ chunks: [ChunkInfo]) async throws {
        pendingQueue = chunks

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.downloadContinuation = continuation
            self.fillDownloadSlots()
        }
    }

    private func fillDownloadSlots() {
        while activeDownloads.count < concurrentSlots, !pendingQueue.isEmpty {
            let chunk = pendingQueue.removeFirst()
            startSingleChunkDownload(chunk)
        }
    }

    private func startSingleChunkDownload(_ chunk: ChunkInfo) {
        guard let url = URL(string: chunk.url) else {
            finishDownloadsWithError(DownloadError.invalidURL(chunk.url))
            return
        }

        let delegate = ChunkDownloadDelegate(
            chunkIndex: chunk.index,
            destinationPath: Self.chunkPath(for: chunk.index),
            onProgress: { [weak self] index, bytesWritten, totalWritten, totalExpected in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let progress = totalExpected > 0
                        ? Double(totalWritten) / Double(totalExpected)
                        : 0
                    self.activeChunkProgress[index] = progress
                    self.recalculateDownloadedBytes()
                    self.speedTracker.recordBytes(bytesWritten)
                    self.downloadSpeed = self.speedTracker.currentSpeed
                }
            },
            onComplete: { [weak self] index, localURL, response, error in
                Task { @MainActor [weak self] in
                    self?.handleChunkComplete(
                        chunkIndex: index, chunk: chunk,
                        localURL: localURL, response: response, error: error
                    )
                }
            }
        )

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 7200
        config.httpMaximumConnectionsPerHost = 1
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)

        activeDownloads[chunk.index] = ActiveDownload(
            session: session, task: task, delegate: delegate
        )
        activeChunkProgress[chunk.index] = 0.0
        task.resume()
    }

    private func handleChunkComplete(
        chunkIndex: Int, chunk: ChunkInfo,
        localURL: URL?, response: URLResponse?, error: Error?
    ) {
        activeDownloads.removeValue(forKey: chunkIndex)
        activeChunkProgress.removeValue(forKey: chunkIndex)

        if _isPaused {
            if activeDownloads.isEmpty {
                downloadContinuation?.resume()
                downloadContinuation = nil
            }
            return
        }

        if let error {
            if (error as NSError).code == NSURLErrorCancelled { return }
            finishDownloadsWithError(error)
            return
        }

        guard localURL != nil,
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            finishDownloadsWithError(DownloadError.chunkDownloadFailed(chunkIndex))
            return
        }

        let destPath = Self.chunkPath(for: chunkIndex)

        do {
            try verifyChecksum(filePath: destPath, expected: chunk.sha256)

            completedIndices.insert(chunkIndex)
            completedChunkCount = completedIndices.count
            saveCompletedIndices()
            recalculateDownloadedBytes()

            fillDownloadSlots()

            if activeDownloads.isEmpty && pendingQueue.isEmpty {
                downloadContinuation?.resume()
                downloadContinuation = nil
            }
        } catch {
            finishDownloadsWithError(error)
        }
    }

    private func finishDownloadsWithError(_ error: Error) {
        for (_, download) in activeDownloads {
            download.session.invalidateAndCancel()
        }
        activeDownloads.removeAll()
        activeChunkProgress.removeAll()
        pendingQueue.removeAll()

        downloadContinuation?.resume(throwing: error)
        downloadContinuation = nil
    }

    private func recalculateDownloadedBytes() {
        guard let manifest else { return }

        let completedBytes = manifest.chunks
            .filter { completedIndices.contains($0.index) }
            .reduce(0 as Int64) { $0 + $1.size }

        let activeBytes: Int64 = activeChunkProgress.reduce(0) { sum, entry in
            let chunk = manifest.chunks.first { $0.index == entry.key }
            return sum + Int64(Double(chunk?.size ?? 0) * entry.value)
        }

        downloadedBytes = completedBytes + activeBytes
    }

    // MARK: - Manifest

    private func fetchManifest() async throws -> Manifest {
        let (data, response) = try await URLSession.shared.data(from: Self.manifestURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DownloadError.manifestFetchFailed
        }
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    // MARK: - Verification

    private func verifyChecksum(filePath: String, expected: String) throws {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
        defer { handle.closeFile() }

        var hasher = SHA256()
        let bufferSize = 16 * 1024 * 1024

        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: bufferSize)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        let computed = digest.map { String(format: "%02x", $0) }.joined()

        if computed != expected {
            throw DownloadError.checksumMismatch(expected: expected, got: computed)
        }
    }

    // MARK: - Decompression

    private func decompressAllChunks(manifest: Manifest) async throws {
        signal(SIGPIPE, SIG_IGN)

        let dest = destinationDir
        let cache = Self.cacheDir
        let bufferSize = Self.pipeStreamBufferSize
        let sortedChunks = manifest.chunks.sorted { $0.index < $1.index }

        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)

            let zstdPaths = ["/usr/local/bin/zstd", "/opt/homebrew/bin/zstd", "/usr/bin/zstd"]
            guard let zstdPath = zstdPaths.first(where: { fm.fileExists(atPath: $0) }) else {
                throw DownloadError.zstdNotFound
            }

            let pipePath = cache + "/decompress.pipe"
            if fm.fileExists(atPath: pipePath) { try fm.removeItem(atPath: pipePath) }
            mkfifo(pipePath, 0o644)

            let stderrPipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "'\(zstdPath)' -d < '\(pipePath)' | tar xf - -C '\(dest)'"]
            process.currentDirectoryURL = URL(fileURLWithPath: dest)
            process.standardError = stderrPipe
            try process.run()

            defer {
                if process.isRunning { process.terminate() }
                try? fm.removeItem(atPath: pipePath)
            }

            guard let pipeHandle = FileHandle(forWritingAtPath: pipePath) else {
                throw DownloadError.decompressionFailed(-1)
            }

            for (fed, chunk) in sortedChunks.enumerated() {
                let chunkPath = Self.chunkPath(for: chunk.index)
                let readHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: chunkPath))
                defer { readHandle.closeFile() }

                while true {
                    let buf = readHandle.readData(ofLength: bufferSize)
                    if buf.isEmpty { break }

                    guard process.isRunning else {
                        let stderrData = stderrPipe.fileHandleForReading.availableData
                        let msg = String(data: stderrData, encoding: .utf8) ?? ""
                        throw DownloadError.decompressionMessage(
                            "Decompression pipeline died at chunk \(chunk.index). \(msg)"
                        )
                    }
                    pipeHandle.write(buf)
                }

                readHandle.closeFile()
                try? fm.removeItem(atPath: chunkPath)

                await MainActor.run {
                    GameDownloader.shared.decompressedChunkCount = fed + 1
                }
            }

            pipeHandle.closeFile()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let stderrData = stderrPipe.fileHandleForReading.availableData
                let msg = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw DownloadError.decompressionMessage(
                    "Exit code \(process.terminationStatus). \(msg)"
                )
            }
        }.value
    }

    // MARK: - Persistence

    private static let completedIndicesKey = "bo3DownloadCompletedChunks"
    private static let destinationDirKey = "bo3DownloadDestination"

    private func saveCompletedIndices() {
        UserDefaults.standard.set(Array(completedIndices), forKey: Self.completedIndicesKey)
        UserDefaults.standard.set(destinationDir, forKey: Self.destinationDirKey)
    }

    private func loadCompletedIndices() -> Set<Int> {
        let arr = UserDefaults.standard.array(forKey: Self.completedIndicesKey) as? [Int] ?? []
        return Set(arr.filter { idx in
            FileManager.default.fileExists(atPath: Self.chunkPath(for: idx))
        })
    }

    private func clearCompletedIndices() {
        UserDefaults.standard.removeObject(forKey: Self.completedIndicesKey)
        UserDefaults.standard.removeObject(forKey: Self.destinationDirKey)
    }

    func loadSavedDestination() -> String? {
        UserDefaults.standard.string(forKey: Self.destinationDirKey)
    }

    func hasPartialDownload() -> Bool {
        !loadCompletedIndices().isEmpty
    }

    func partialDownloadCount() -> Int {
        loadCompletedIndices().count
    }

    // MARK: - Helpers

    nonisolated private static func chunkPath(for index: Int) -> String {
        cacheDir + "/chunk-\(String(format: "%03d", index)).bin"
    }

    // MARK: - Errors

    enum DownloadError: LocalizedError {
        case manifestFetchFailed
        case invalidURL(String)
        case chunkDownloadFailed(Int)
        case checksumMismatch(expected: String, got: String)
        case decompressionFailed(Int32)
        case decompressionMessage(String)
        case zstdNotFound

        var errorDescription: String? {
            switch self {
            case .manifestFetchFailed:
                return "Failed to fetch game manifest from server."
            case let .invalidURL(url):
                return "Invalid chunk URL: \(url)"
            case let .chunkDownloadFailed(idx):
                return "Failed to download chunk \(idx)."
            case let .checksumMismatch(expected, got):
                return "Checksum mismatch — expected \(expected.prefix(12))..., got \(got.prefix(12))..."
            case let .decompressionFailed(code):
                return "Decompression failed (exit code \(code))."
            case let .decompressionMessage(msg):
                return "Decompression failed: \(msg)"
            case .zstdNotFound:
                return "zstd not found. Install it with: brew install zstd"
            }
        }
    }
}

// MARK: - Download Delegate

private class ChunkDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let chunkIndex: Int
    let destinationPath: String
    var onProgress: (Int, Int64, Int64, Int64) -> Void
    var onComplete: (Int, URL?, URLResponse?, Error?) -> Void
    private var didCallComplete = false

    init(chunkIndex: Int,
         destinationPath: String,
         onProgress: @escaping (Int, Int64, Int64, Int64) -> Void,
         onComplete: @escaping (Int, URL?, URLResponse?, Error?) -> Void) {
        self.chunkIndex = chunkIndex
        self.destinationPath = destinationPath
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    private func fireComplete(_ index: Int, _ url: URL?, _ response: URLResponse?, _ error: Error?) {
        guard !didCallComplete else { return }
        didCallComplete = true
        onComplete(index, url, response, error)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(chunkIndex, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let dest = URL(fileURLWithPath: destinationPath)
        let fm = FileManager.default
        do {
            let parentDir = dest.deletingLastPathComponent().path
            if !fm.fileExists(atPath: parentDir) {
                try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: destinationPath) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: location, to: dest)
            fireComplete(chunkIndex, dest, downloadTask.response, nil)
        } catch {
            do {
                let dest2 = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("bo3-chunk-\(chunkIndex).bin")
                if fm.fileExists(atPath: dest2.path) { try fm.removeItem(at: dest2) }
                try fm.copyItem(at: location, to: dest2)
                let parentDir = URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
                try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                if fm.fileExists(atPath: destinationPath) {
                    try fm.removeItem(atPath: destinationPath)
                }
                try fm.moveItem(at: dest2, to: URL(fileURLWithPath: destinationPath))
                fireComplete(chunkIndex, URL(fileURLWithPath: destinationPath), downloadTask.response, nil)
            } catch let fallbackError {
                fireComplete(chunkIndex, nil, downloadTask.response, fallbackError)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            fireComplete(chunkIndex, nil, task.response, error)
        }
    }
}

// MARK: - Speed Tracker

private struct SpeedTracker {
    private var samples: [(time: Date, bytes: Int64)] = []
    private let windowSize: TimeInterval = 3.0

    var currentSpeed: Double {
        let now = Date()
        let recent = samples.filter { now.timeIntervalSince($0.time) <= windowSize }
        guard recent.count >= 2 else { return 0 }
        let totalBytes = recent.reduce(0 as Int64) { $0 + $1.bytes }
        let elapsed = recent.last!.time.timeIntervalSince(recent.first!.time)
        return elapsed > 0 ? Double(totalBytes) / elapsed : 0
    }

    mutating func recordBytes(_ bytes: Int64) {
        let now = Date()
        samples.append((time: now, bytes: bytes))
        samples.removeAll { now.timeIntervalSince($0.time) > windowSize * 2 }
    }
}
