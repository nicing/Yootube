@preconcurrency import AVFoundation
import Combine
import Foundation

struct VideoCacheEntry: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let videoID: String
    let title: String
    let author: String
    let authorID: String
    let qualityHeight: Int
    let cachedAt: Date
    let byteCount: Int64
    let captions: [CachedVideoCaption]

    var id: String { videoID }

    var basicMetadata: VideoMetadata {
        VideoMetadata(
            videoId: videoID,
            title: title,
            author: author,
            authorId: authorID,
            description: nil,
            viewCount: nil,
            likeCount: nil,
            publishedText: nil,
            subCountText: nil,
            authorThumbnails: nil,
            recommendedVideos: nil,
            formatStreams: nil,
            adaptiveFormats: nil,
            captions: nil,
            lengthSeconds: nil
        )
    }
}

struct CachedVideoCaption: Codable, Equatable, Sendable {
    let label: String
    let languageCode: String
    let fileName: String
}

@MainActor
final class VideoCacheStore: ObservableObject {
    static let shared = VideoCacheStore()

    @Published private(set) var entries: [String: VideoCacheEntry] = [:]
    @Published private(set) var cachingVideoIDs: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    let rootDirectory: URL
    private let session: URLSession
    private var tasks: [String: Task<Void, Never>] = [:]

    init(rootDirectory: URL = VideoCacheStore.defaultDirectory,
         session: URLSession = .shared) {
        self.rootDirectory = rootDirectory
        self.session = session
        reload()
    }

    static let defaultDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0]
        .appendingPathComponent("Yootube", isDirectory: true)
        .appendingPathComponent("VideoCache", isDirectory: true)

    var totalByteCount: Int64 { entries.values.reduce(0) { $0 + $1.byteCount } }
    var isCaching: Bool { !cachingVideoIDs.isEmpty }

    func entry(for videoID: String) -> VideoCacheEntry? {
        entries[videoID]
    }

    func isCaching(_ videoID: String) -> Bool {
        cachingVideoIDs.contains(videoID)
    }

    func error(for videoID: String) -> String? {
        errors[videoID]
    }

    func dismissError(for videoID: String) {
        errors.removeValue(forKey: videoID)
    }

    func cache(_ video: VideoMetadata, option: VideoCacheOption) {
        guard !isCaching(video.videoId),
              video.cacheOptions.contains(option),
              VideoRoute.watchURL(id: video.videoId) != nil else { return }

        let captionRequests = (video.captions ?? []).enumerated().compactMap { index, caption in
            VideoAPI.captionURL(caption.url, videoID: video.videoId).map {
                VideoCacheCaptionRequest(
                    label: caption.label,
                    languageCode: caption.languageCode,
                    sourceURL: $0,
                    fileName: "caption-\(index).vtt"
                )
            }
        }
        let request = VideoCacheRequest(
            videoID: video.videoId,
            title: video.title,
            author: video.author,
            authorID: video.authorId,
            qualityHeight: option.height,
            videoURL: option.videoURL,
            videoByteCount: option.videoByteCount,
            audioURL: option.audioURL,
            audioByteCount: option.audioByteCount,
            captions: captionRequests
        )

        errors.removeValue(forKey: video.videoId)
        cachingVideoIDs.insert(video.videoId)
        let rootDirectory = rootDirectory
        let session = session
        tasks[video.videoId] = Task { [weak self] in
            do {
                let entry = try await VideoCacheWorker.create(
                    request: request, rootDirectory: rootDirectory, session: session
                )
                guard let self else { return }
                entries[entry.videoID] = entry
            } catch is CancellationError {
                // A cancelled cache never replaces the previous complete entry.
            } catch {
                guard let self else { return }
                errors[request.videoID] = VideoCacheWorker.userMessage(for: error)
            }
            self?.cachingVideoIDs.remove(request.videoID)
            self?.tasks.removeValue(forKey: request.videoID)
        }
    }

    func remove(videoID: String) throws {
        guard !isCaching(videoID) else { return }
        let directory = directory(for: videoID)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        entries.removeValue(forKey: videoID)
        errors.removeValue(forKey: videoID)
    }

    func removeAll() throws {
        guard !isCaching else { return }
        if FileManager.default.fileExists(atPath: rootDirectory.path) {
            try FileManager.default.removeItem(at: rootDirectory)
        }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        entries.removeAll()
        errors.removeAll()
    }

    func reload() {
        var loaded: [String: VideoCacheEntry] = [:]
        let fileManager = FileManager.default
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            entries = loaded
            return
        }

        for directory in directories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let entry = try? Self.readEntry(in: directory),
                  entry.videoID == directory.lastPathComponent,
                  VideoRoute.watchURL(id: entry.videoID) != nil else { continue }
            loaded[entry.videoID] = entry
        }
        entries = loaded
    }

    func playerPageURL(for videoID: String, startValue: String?) -> URL? {
        guard entries[videoID] != nil else { return nil }
        var components = URLComponents(url: directory(for: videoID)
            .appendingPathComponent("player.html"), resolvingAgainstBaseURL: false)
        if let startValue, !startValue.isEmpty { components?.fragment = "t=\(startValue)" }
        return components?.url
    }

    func videoFileURL(for videoID: String) -> URL? {
        guard entries[videoID] != nil else { return nil }
        return directory(for: videoID).appendingPathComponent("video.mp4")
    }

    func readAccessURL(for videoID: String) -> URL? {
        entries[videoID].map { _ in directory(for: videoID) }
    }

    func isPlayerPage(_ url: URL, videoID: String) -> Bool {
        guard entries[videoID] != nil, url.isFileURL else { return false }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url?.standardizedFileURL == directory(for: videoID)
            .appendingPathComponent("player.html").standardizedFileURL
    }

    private func directory(for videoID: String) -> URL {
        rootDirectory.appendingPathComponent(videoID, isDirectory: true)
    }

    private static func readEntry(in directory: URL) throws -> VideoCacheEntry {
        let manifest = directory.appendingPathComponent("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(VideoCacheEntry.self, from: Data(contentsOf: manifest))
        guard entry.schemaVersion == VideoCacheEntry.currentSchemaVersion,
              entry.qualityHeight > 0,
              entry.byteCount > 0,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("video.mp4").path),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("player.html").path) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return entry
    }
}

private struct VideoCacheRequest: Sendable {
    let videoID: String
    let title: String
    let author: String
    let authorID: String
    let qualityHeight: Int
    let videoURL: URL
    let videoByteCount: Int64?
    let audioURL: URL?
    let audioByteCount: Int64?
    let captions: [VideoCacheCaptionRequest]
}

private struct VideoCacheCaptionRequest: Sendable {
    let label: String
    let languageCode: String
    let sourceURL: URL
    let fileName: String
}

private enum VideoCacheWorker {
    enum Failure: Error {
        case invalidResponse
        case emptyFile
        case missingTrack
        case exportFailed
    }

    static func create(request: VideoCacheRequest, rootDirectory: URL,
                       session: URLSession) async throws -> VideoCacheEntry {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootDirectory.path)

        let staging = rootDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var committed = false
        defer { if !committed { try? fileManager.removeItem(at: staging) } }

        let sourceVideo = staging.appendingPathComponent("source-video.mp4")
        let output = staging.appendingPathComponent("video.mp4")
        if let audioURL = request.audioURL {
            let sourceAudio = staging.appendingPathComponent("source-audio.m4a")
            async let videoDownload: Void = VideoCacheDownloader.download(
                request.videoURL,
                to: sourceVideo,
                session: session,
                expectedByteCount: request.videoByteCount,
                segmentByteCount: 4 * 1_024 * 1_024
            )
            async let audioDownload: Void = VideoCacheDownloader.download(
                audioURL,
                to: sourceAudio,
                session: session,
                expectedByteCount: request.audioByteCount,
                segmentByteCount: 512 * 1_024
            )
            _ = try await (videoDownload, audioDownload)
            try await mux(video: sourceVideo, audio: sourceAudio, to: output)
            try? fileManager.removeItem(at: sourceVideo)
            try? fileManager.removeItem(at: sourceAudio)
        } else {
            try await VideoCacheDownloader.download(
                request.videoURL,
                to: output,
                session: session,
                expectedByteCount: request.videoByteCount
            )
        }

        var cachedCaptions: [CachedVideoCaption] = []
        for caption in request.captions.prefix(100) {
            let destination = staging.appendingPathComponent(caption.fileName)
            do {
                try await VideoCacheDownloader.download(
                    caption.sourceURL,
                    to: destination,
                    session: session,
                    maximumBytes: 10 * 1_024 * 1_024
                )
                cachedCaptions.append(CachedVideoCaption(
                    label: caption.label,
                    languageCode: caption.languageCode,
                    fileName: caption.fileName
                ))
            } catch {
                try? fileManager.removeItem(at: destination)
            }
        }

        let outputSize = try fileSize(of: output)
        let captionsSize = try cachedCaptions.reduce(Int64(0)) { partial, caption in
            partial + (try fileSize(of: staging.appendingPathComponent(caption.fileName)))
        }
        let entry = VideoCacheEntry(
            schemaVersion: VideoCacheEntry.currentSchemaVersion,
            videoID: request.videoID,
            title: request.title,
            author: request.author,
            authorID: request.authorID,
            qualityHeight: request.qualityHeight,
            cachedAt: Date(),
            byteCount: outputSize + captionsSize,
            captions: cachedCaptions
        )
        try CachedVideoPlayerDocument.html(
            qualityHeight: request.qualityHeight, captions: cachedCaptions
        ).write(to: staging.appendingPathComponent("player.html"), atomically: true, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entry).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)

        let destination = rootDirectory.appendingPathComponent(request.videoID, isDirectory: true)
        try replaceDirectory(at: destination, with: staging)
        committed = true
        return entry
    }

    static func userMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return L10n.t("缓存失败，磁盘可用空间不足。")
        }
        return L10n.t("视频缓存失败，请检查网络和磁盘空间后重试。")
    }

    private static func mux(video videoURL: URL, audio audioURL: URL, to outputURL: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw Failure.missingTrack
        }

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ), let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw Failure.missingTrack }
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideoTrack, at: .zero
        )
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        try audioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: min(videoDuration, audioDuration)),
            of: sourceAudioTrack,
            at: .zero
        )

        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetPassthrough
        ) else { throw Failure.exportFailed }
        exporter.shouldOptimizeForNetworkUse = true
        if #available(macOS 15.0, *) {
            try await exporter.export(to: outputURL, as: .mp4)
        } else {
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            await withCheckedContinuation { continuation in
                exporter.exportAsynchronously { continuation.resume() }
            }
            guard exporter.status == .completed else { throw exporter.error ?? Failure.exportFailed }
        }
        guard try fileSize(of: outputURL) > 0 else { throw Failure.emptyFile }
    }

    private static func replaceDirectory(at destination: URL, with staging: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path) else {
            try fileManager.moveItem(at: staging, to: destination)
            return
        }
        let backup = destination.deletingLastPathComponent()
            .appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.moveItem(at: destination, to: backup)
        do {
            try fileManager.moveItem(at: staging, to: destination)
            try? fileManager.removeItem(at: backup)
        } catch {
            try? fileManager.moveItem(at: backup, to: destination)
            throw error
        }
    }

    private static func fileSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0 else { throw Failure.emptyFile }
        return Int64(size)
    }
}

enum VideoCacheDownloader {
    enum Failure: Error {
        case invalidResponse
        case emptyFile
    }

    static func download(
        _ source: URL,
        to destination: URL,
        session: URLSession,
        expectedByteCount: Int64? = nil,
        segmentByteCount: Int64 = 4 * 1_024 * 1_024,
        maximumBytes: Int64? = nil
    ) async throws {
        guard let expectedByteCount, expectedByteCount > 0 else {
            try await downloadSingleResponse(
                source, to: destination, session: session, maximumBytes: maximumBytes
            )
            return
        }
        guard segmentByteCount > 0,
              maximumBytes.map({ expectedByteCount <= $0 }) ?? true else {
            throw Failure.invalidResponse
        }

        try Data().write(to: destination, options: .atomic)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        do {
            var offset: Int64 = 0
            while offset < expectedByteCount {
                try Task.checkCancellation()
                let end = min(expectedByteCount - 1, offset + segmentByteCount - 1)
                let data = try await rangedData(
                    source,
                    range: offset...end,
                    expectedByteCount: expectedByteCount,
                    session: session
                )
                try output.write(contentsOf: data)
                offset += Int64(data.count)
            }
            guard try fileSize(of: destination) == expectedByteCount else {
                throw Failure.invalidResponse
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func rangedData(
        _ source: URL,
        range: ClosedRange<Int64>,
        expectedByteCount: Int64,
        session: URLSession
    ) async throws -> Data {
        var lastError: Error = Failure.invalidResponse
        for attempt in 0..<3 {
            do {
                var request = URLRequest(url: source)
                request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 206,
                      let responseRange = contentRange(http.value(forHTTPHeaderField: "Content-Range")),
                      responseRange.start == range.lowerBound,
                      responseRange.end <= range.upperBound,
                      responseRange.total == expectedByteCount,
                      !data.isEmpty,
                      Int64(data.count) <= responseRange.end - responseRange.start + 1 else {
                    throw Failure.invalidResponse
                }
                return data
            } catch {
                if error is CancellationError { throw error }
                lastError = error
                if attempt < 2 { try await Task.sleep(for: .milliseconds(300)) }
            }
        }
        throw lastError
    }

    private static func contentRange(_ value: String?) -> (start: Int64, end: Int64, total: Int64)? {
        guard let value,
              value.hasPrefix("bytes "),
              let slash = value.firstIndex(of: "/"),
              let dash = value[..<slash].lastIndex(of: "-") else { return nil }
        let startText = value[value.index(value.startIndex, offsetBy: 6)..<dash]
        let endText = value[value.index(after: dash)..<slash]
        let totalText = value[value.index(after: slash)...]
        guard let start = Int64(startText), let end = Int64(endText), let total = Int64(totalText),
              start >= 0, end >= start, total > end else { return nil }
        return (start, end, total)
    }

    private static func downloadSingleResponse(
        _ source: URL,
        to destination: URL,
        session: URLSession,
        maximumBytes: Int64?
    ) async throws {
        let (temporary, response) = try await session.download(from: source)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.invalidResponse
        }
        let size = try fileSize(of: temporary)
        guard size > 0 else { throw Failure.emptyFile }
        if let maximumBytes, size > maximumBytes { throw Failure.invalidResponse }
        try FileManager.default.copyItem(at: temporary, to: destination)
    }

    private static func fileSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else { throw Failure.emptyFile }
        return Int64(size)
    }
}

private enum CachedVideoPlayerDocument {
    static func html(qualityHeight: Int, captions: [CachedVideoCaption]) -> String {
        let tracks = captions.map {
            "<track kind=\"subtitles\" label=\"\(escape($0.label))\" srclang=\"\(escape($0.languageCode))\" src=\"\(escape($0.fileName))\">"
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body,#player,.vjs-tech{width:100%;height:100%;margin:0;background:#000;overflow:hidden}.vjs-tech{display:block;object-fit:contain}</style>
        </head><body><div id="player" class="video-js"><video class="vjs-tech" data-quality="\(L10n.t("\(qualityHeight)p（本地缓存）"))" autoplay playsinline preload="auto" src="video.mp4">\(tracks)</video><div class="vjs-text-track-display"></div></div></body></html>
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
