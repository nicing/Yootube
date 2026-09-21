import Foundation

struct VideoMetadata: Decodable {
    let videoId: String
    let title: String
    let author: String
    let authorId: String
    let description: String?
    let viewCount: Int?
    let likeCount: Int?
    let publishedText: String?
    let subCountText: String?
    let authorThumbnails: [VideoThumbnail]?
    let recommendedVideos: [RecommendedVideo]?
    let formatStreams: [VideoFormat]?
    let adaptiveFormats: [VideoFormat]?
    let captions: [VideoCaption]?
    let lengthSeconds: Int?

    var pictureInPictureURL: URL? {
        (formatStreams ?? [])
            .filter { $0.isMP4 && VideoStreamProxy.upstreamURL(for: $0) != nil }
            .max {
                if $0.qualityHeight == $1.qualityHeight {
                    return ($0.bitrate ?? 0) < ($1.bitrate ?? 0)
                }
                return $0.qualityHeight < $1.qualityHeight
            }
            .flatMap(VideoStreamProxy.upstreamURL)
    }

    var cacheOptions: [VideoCacheOption] {
        var bestStreamByHeight: [Int: VideoFormat] = [:]
        for stream in formatStreams ?? [] {
            let height = stream.qualityHeight
            guard stream.isMP4, height > 0, VideoStreamProxy.localURL(for: stream) != nil else { continue }
            if let existing = bestStreamByHeight[height],
               (existing.bitrate ?? 0) >= (stream.bitrate ?? 0) { continue }
            bestStreamByHeight[height] = stream
        }

        var options = bestStreamByHeight.compactMap { height, stream -> VideoCacheOption? in
            guard let videoURL = VideoStreamProxy.localURL(for: stream) else { return nil }
            return VideoCacheOption(
                height: height,
                videoURL: videoURL,
                videoByteCount: stream.contentLength,
                audioURL: nil,
                audioByteCount: nil
            )
        }

        let audio = (adaptiveFormats ?? [])
            .filter { $0.isAACAudio && VideoStreamProxy.localURL(for: $0) != nil }
            .max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
        if let audio, let audioURL = VideoStreamProxy.localURL(for: audio) {
            var bestAdaptiveByHeight: [Int: VideoFormat] = [:]
            for stream in adaptiveFormats ?? [] {
                let height = stream.qualityHeight
                guard stream.isH264Video, height > 0, height <= 1080,
                      bestStreamByHeight[height] == nil,
                      VideoStreamProxy.localURL(for: stream) != nil else { continue }
                if let existing = bestAdaptiveByHeight[height],
                   (existing.bitrate ?? 0) >= (stream.bitrate ?? 0) { continue }
                bestAdaptiveByHeight[height] = stream
            }
            options.append(contentsOf: bestAdaptiveByHeight.compactMap { height, stream in
                guard let videoURL = VideoStreamProxy.localURL(for: stream) else { return nil }
                return VideoCacheOption(
                    height: height,
                    videoURL: videoURL,
                    videoByteCount: stream.contentLength,
                    audioURL: audioURL,
                    audioByteCount: audio.contentLength
                )
            })
        }

        return options.sorted { $0.height > $1.height }
    }
}

struct VideoThumbnail: Decodable {
    let url: String
    let width: Int?
}

struct VideoFormat: Decodable {
    let url: String
    let type: String?
    let container: String?
    let qualityLabel: String?
    let bitrate: Int?
    let contentLength: Int64?

    private enum CodingKeys: String, CodingKey {
        case url, type, container, qualityLabel, bitrate
        case contentLength = "clen"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decode(String.self, forKey: .url)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        container = try values.decodeIfPresent(String.self, forKey: .container)
        qualityLabel = try values.decodeIfPresent(String.self, forKey: .qualityLabel)
        if let value = try? values.decode(Int.self, forKey: .bitrate) {
            bitrate = value
        } else if let value = try? values.decode(String.self, forKey: .bitrate) {
            bitrate = Int(value)
        } else {
            bitrate = nil
        }
        if let value = try? values.decode(Int64.self, forKey: .contentLength) {
            contentLength = value
        } else if let value = try? values.decode(String.self, forKey: .contentLength) {
            contentLength = Int64(value)
        } else {
            contentLength = nil
        }
    }

    var isMP4: Bool {
        container?.lowercased() == "mp4" || type?.lowercased().hasPrefix("video/mp4") == true
    }

    var isH264Video: Bool {
        isMP4 && type?.lowercased().hasPrefix("video/mp4") == true &&
            type?.lowercased().contains("avc1") == true
    }

    var isAACAudio: Bool {
        let loweredType = type?.lowercased()
        return (container?.lowercased() == "m4a" || loweredType?.hasPrefix("audio/mp4") == true) &&
            loweredType?.contains("mp4a") == true
    }

    var qualityHeight: Int {
        guard let qualityLabel else { return 0 }
        return Int(qualityLabel.prefix { $0.isNumber }) ?? 0
    }
}

struct VideoCaption: Decodable, Sendable {
    let label: String
    let languageCode: String
    let url: String

    private enum CodingKeys: String, CodingKey {
        case label, url
        case languageCode = "language_code"
    }
}

struct VideoCacheOption: Identifiable, Equatable, Sendable {
    let height: Int
    let videoURL: URL
    let videoByteCount: Int64?
    let audioURL: URL?
    let audioByteCount: Int64?

    var id: String { "\(height)-\(videoURL.absoluteString)-\(audioURL?.absoluteString ?? "muxed")" }
    var requiresMuxing: Bool { audioURL != nil }
}

enum VideoStreamProxy {
    static func localURL(for stream: VideoFormat) -> URL? {
        guard let url = URL(string: stream.url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let local = LocalServiceManager.invidiousURL
        guard url.scheme == local.scheme, url.host == local.host, url.port == local.port,
              ["/videoplayback", "/companion/videoplayback"].contains(url.path) else { return nil }
        components.percentEncodedPath = "/companion/videoplayback"
        return components.url
    }

    static func upstreamURL(for stream: VideoFormat) -> URL? {
        guard let url = URL(string: stream.url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let local = LocalServiceManager.invidiousURL
        guard url.scheme == local.scheme, url.host == local.host, url.port == local.port,
              ["/videoplayback", "/companion/videoplayback"].contains(url.path) else { return nil }

        let hostItems = components.queryItems?.filter { $0.name == "host" } ?? []
        guard hostItems.count == 1,
              let host = hostItems[0].value?.lowercased(),
              isAllowedGoogleVideoHost(host) else { return nil }

        components.scheme = "https"
        components.host = host
        components.port = nil
        components.user = nil
        components.password = nil
        components.percentEncodedPath = "/videoplayback"
        components.queryItems = components.queryItems?.filter { $0.name != "host" }

        guard let upstream = components.url,
              upstream.scheme == "https", upstream.user == nil, upstream.password == nil,
              upstream.port == nil, upstream.path == "/videoplayback",
              upstream.host.map(isAllowedGoogleVideoHost) == true else {
            return nil
        }
        return upstream
    }

    private static func isAllowedGoogleVideoHost(_ host: String) -> Bool {
        guard !host.isEmpty, !host.hasPrefix("."), !host.hasSuffix("."), !host.contains(".."),
              host.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...122).contains(byte) || byte == 45 || byte == 46
              }) else { return false }
        return host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
    }
}

struct RecommendedVideo: Decodable, Identifiable {
    let videoId: String
    let title: String
    let author: String?
    let viewCountText: String?
    let lengthSeconds: Int?
    var id: String { videoId }
    var url: URL? { VideoRoute.watchURL(id: videoId) }
}

struct VideoComment: Decodable, Identifiable {
    let commentId: String
    let author: String
    let content: String
    let publishedText: String?
    let likeCount: Int?
    var id: String { commentId }
}

struct VideoComments: Decodable {
    let comments: [VideoComment]
    let commentCount: Int?
    let continuation: String?
}

enum VideoAPI {
    static func fetch<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: LocalServiceManager.invidiousURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var localizedQuery = query
        let language = AppLanguage.current
        if !localizedQuery.contains(where: { $0.name == "hl" }) {
            localizedQuery.append(URLQueryItem(name: "hl", value: language.invidiousLanguageCode))
        }
        components.queryItems = localizedQuery
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 35
        request.setValue(language.acceptLanguageHeader, forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.unavailable
        }
        return try JSONDecoder().decode(type, from: data)
    }

    // Channel artwork requests also go through our own service.
    static func imageURL(_ source: String?) -> URL? {
        guard var source, !source.isEmpty else { return nil }
        if source.hasPrefix("//") { source = "https:" + source }
        guard let original = URLComponents(string: source),
              ["yt3.ggpht.com", "yt3.googleusercontent.com"].contains(original.host ?? "") else { return nil }
        var local = URLComponents(url: LocalServiceManager.invidiousURL, resolvingAgainstBaseURL: false)!
        local.percentEncodedPath = "/ggpht" + original.percentEncodedPath
        local.percentEncodedQuery = original.percentEncodedQuery
        return local.url
    }

    static func avatarURL(_ source: String?) -> URL? { imageURL(source) }

    static func captionURL(_ source: String, videoID: String) -> URL? {
        guard let relative = URL(string: source, relativeTo: LocalServiceManager.invidiousURL)?.absoluteURL,
              let components = URLComponents(url: relative, resolvingAgainstBaseURL: false) else { return nil }
        let local = LocalServiceManager.invidiousURL
        guard relative.scheme == local.scheme, relative.host == local.host, relative.port == local.port,
              relative.path == "/api/v1/captions/\(videoID)",
              components.queryItems?.contains(where: { $0.name == "label" && $0.value?.isEmpty == false }) == true else {
            return nil
        }
        return relative
    }

    static func thumbnailURL(_ videoID: String) -> URL {
        LocalServiceManager.invidiousURL.appendingPathComponent("vi/\(videoID)/mqdefault.jpg")
    }

    enum APIError: LocalizedError {
        case unavailable
        var errorDescription: String? { L10n.t("暂时无法获取视频数据，请稍后重试。") }
    }
}

@MainActor
enum VideoRequestRetry {
    static func run<Value>(
        maxAttempts: Int,
        delay: Duration,
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        operation: () async throws -> Value
    ) async throws -> Value {
        precondition(maxAttempts > 0)
        var lastError: Error?

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                let value = try await operation()
                try Task.checkCancellation()
                return value
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < maxAttempts else { break }
                try await sleep(delay)
            }
        }

        throw lastError ?? VideoAPI.APIError.unavailable
    }
}

struct VideoRoute: Equatable {
    let id: String
    let source: URL
    let embedURL: URL

    var startTimeValue: String? {
        URLComponents(url: source, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "t" || $0.name == "start" })?.value
    }

    static func watchURL(id: String) -> URL? {
        guard isValidID(id) else { return nil }
        var url = URLComponents(url: LocalServiceManager.invidiousURL.appendingPathComponent("watch"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "v", value: id)]
        return url.url
    }

    static func youtubeURL(id: String) -> URL? {
        guard isValidID(id) else { return nil }
        var url = URLComponents(string: "https://www.youtube.com/watch")!
        url.queryItems = [URLQueryItem(name: "v", value: id)]
        return url.url
    }

    private static func isValidID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    init?(_ url: URL) {
        let base = LocalServiceManager.invidiousURL
        guard url.scheme == base.scheme, url.host == base.host, url.port == base.port,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let id: String?
        if url.path == "/watch" {
            id = parts.queryItems?.first(where: { $0.name == "v" })?.value
        } else if url.path.hasPrefix("/embed/"), url.path.split(separator: "/").count == 2 {
            id = url.path.split(separator: "/").dropFirst().first.map(String.init)
        } else { return nil }
        guard let id, Self.isValidID(id) else { return nil }
        self.id = id
        self.source = url
        var embed = URLComponents(url: base.appendingPathComponent("embed").appendingPathComponent(id), resolvingAgainstBaseURL: false)!
        var query = (parts.queryItems ?? []).filter { ["t", "start", "list", "index", "listen"].contains($0.name) }
        if !query.contains(where: { $0.name == "t" }), let start = query.first(where: { $0.name == "start" })?.value {
            query.append(URLQueryItem(name: "t", value: start))
        }
        query.append(contentsOf: [
            URLQueryItem(name: "local", value: "true"),
            URLQueryItem(name: "autoplay", value: "1")
        ])
        embed.queryItems = query
        self.embedURL = embed.url!
    }
}
