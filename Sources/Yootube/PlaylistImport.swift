import Foundation

struct PlaylistImportRoute: Equatable, Hashable, Identifiable {
    enum Kind: Equatable, Hashable { case playlist, mix }

    let kind: Kind
    let id: String
    let continuation: String?

    var sourceID: String { "\(kind == .mix ? "mix" : "playlist"):\(id)" }

    init?(_ url: URL) {
        let base = LocalServiceManager.invidiousURL
        guard url.scheme == base.scheme, url.host == base.host, url.port == base.port,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["/playlist", "/mix"].contains(parts.path),
              let id = parts.queryItems?.first(where: { $0.name == "list" })?.value,
              Self.isValidID(id) else { return nil }
        self.kind = parts.path == "/mix" || id.hasPrefix("RD") ? .mix : .playlist
        self.id = id
        self.continuation = parts.queryItems?.first(where: { $0.name == "continuation" })?.value
    }

    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 200 &&
        id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}

struct PlaylistImport {
    let title: String
    let author: String?
    let description: String?
    let videoCount: Int?
    let viewCount: Int?
    let videos: [FavoriteVideo]
    let items: [PlaylistVideoItem]
}

struct PlaylistVideoItem: Identifiable {
    let videoID: String
    let title: String
    let author: String
    let index: Int?
    let lengthSeconds: Int?
    let position: Int

    var id: String { "\(position):\(videoID)" }
}

enum PlaylistImportAPI {
    static func fetch(_ route: PlaylistImportRoute) async throws -> PlaylistImport {
        if route.kind == .mix {
            let response = try await page(
                path: "api/v1/mixes/\(route.id)",
                query: route.continuation.map { [URLQueryItem(name: "continuation", value: $0)] } ?? []
            )
            return makeImport(response, videos: response.videos)
        }

        var offset = 0
        var title = "YouTube Playlist"
        var expectedCount: Int?
        var metadata: PlaylistImportResponse?
        var collected: [PlaylistImportVideo] = []
        var knownIndexes = Set<Int>()

        // The local API returns at most 200 YouTube playlist items per page.
        // Continue by item index, and stop if the source no longer advances.
        for _ in 0..<50 {
            let response = try await page(
                path: "api/v1/playlists/\(route.id)",
                query: offset == 0 ? [] : [URLQueryItem(name: "index", value: String(offset))]
            )
            if metadata == nil { metadata = response }
            title = response.title
            expectedCount = response.videoCount
            let newVideos = response.videos.filter { video in
                guard let index = video.index else { return true }
                return knownIndexes.insert(index).inserted
            }
            collected.append(contentsOf: newVideos)
            if let expectedCount, collected.count >= expectedCount { break }
            guard let next = response.videos.compactMap(\.index).max().map({ $0 + 1 }),
                  next > offset, !newVideos.isEmpty else { break }
            offset = next
        }
        guard let first = metadata else { throw VideoAPI.APIError.unavailable }
        return makeImport(PlaylistImportResponse(title: title,
                                                 author: first.author,
                                                 description: first.description,
                                                 videoCount: expectedCount,
                                                 viewCount: first.viewCount,
                                                 videos: collected),
                          videos: collected)
    }

    private static func page(path: String, query: [URLQueryItem]) async throws -> PlaylistImportResponse {
        try await VideoAPI.fetch(PlaylistImportResponse.self, path: path, query: query)
    }

    private static func makeImport(_ response: PlaylistImportResponse,
                                   videos: [PlaylistImportVideo]) -> PlaylistImport {
        let items = displayItems(from: videos, fallbackAuthor: response.author)
        let savedAt = Date()
        var savedIDs = Set<String>()
        return PlaylistImport(title: response.title,
                              author: response.author,
                              description: response.description,
                              videoCount: response.videoCount,
                              viewCount: response.viewCount,
                              videos: items.compactMap {
                                  guard savedIDs.insert($0.videoID).inserted else { return nil }
                                  return FavoriteVideo(id: $0.videoID, title: $0.title,
                                                       author: $0.author, savedAt: savedAt)
                              },
                              items: items)
    }

    private static func displayItems(from videos: [PlaylistImportVideo],
                                     fallbackAuthor: String?) -> [PlaylistVideoItem] {
        return videos.enumerated().compactMap { offset, video in
            guard let id = video.videoId, let title = video.title,
                  VideoRoute.watchURL(id: id) != nil else { return nil }
            let author = video.author?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayAuthor = author?.isEmpty == false ? author : fallbackAuthor
            return PlaylistVideoItem(videoID: id, title: title,
                                     author: displayAuthor ?? "",
                                     index: video.index, lengthSeconds: video.lengthSeconds,
                                     position: video.index ?? offset)
        }
    }
}

private struct PlaylistImportResponse: Decodable {
    let title: String
    let author: String?
    let description: String?
    let videoCount: Int?
    let viewCount: Int?
    let videos: [PlaylistImportVideo]
}

private struct PlaylistImportVideo: Decodable {
    let videoId: String?
    let title: String?
    let author: String?
    let index: Int?
    let lengthSeconds: Int?
}
