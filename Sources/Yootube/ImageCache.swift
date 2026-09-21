import AppKit
import Foundation
import SwiftUI

actor ImageCacheStore {
    static let diskCapacityBytes = 300 * 1024 * 1024
    static let shared: ImageCacheStore = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("com.local.yootube/ImageCache", isDirectory: true)
        let cache = URLCache(
            memoryCapacity: memoryCapacityBytes,
            diskCapacity: diskCapacityBytes,
            directory: directory
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return ImageCacheStore(cache: cache, session: URLSession(configuration: configuration))
    }()

    private static let memoryCapacityBytes = 64 * 1024 * 1024
    private static let maximumImageBytes = 25 * 1024 * 1024
    private let cache: URLCache
    private let session: URLSession
    private var generation = 0
    private var inFlight: [URL: InFlightRequest] = [:]

    init(cache: URLCache, session: URLSession) {
        self.cache = cache
        self.session = session
    }

    var currentDiskUsageBytes: Int { cache.currentDiskUsage }

    func data(for url: URL) async throws -> Data {
        let cachedRequest = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 30
        )
        if let cached = cache.cachedResponse(for: cachedRequest),
           Self.isValidImage(cached.data, response: cached.response) {
            return cached.data
        }
        cache.removeCachedResponse(for: cachedRequest)

        let requestGeneration = generation
        if let existing = inFlight[url], existing.generation == requestGeneration {
            return try await existing.task.value.data
        }

        var networkRequest = cachedRequest
        networkRequest.cachePolicy = .reloadIgnoringLocalCacheData
        let requestID = UUID()
        let session = self.session
        let task = Task {
            try await Self.downloadImage(using: session, request: networkRequest)
        }
        inFlight[url] = InFlightRequest(id: requestID, generation: requestGeneration, task: task)

        do {
            let downloaded = try await task.value
            if inFlight[url]?.id == requestID { inFlight[url] = nil }
            if generation == requestGeneration {
                cache.storeCachedResponse(
                    CachedURLResponse(
                        response: downloaded.response,
                        data: downloaded.data,
                        storagePolicy: .allowed
                    ),
                    for: cachedRequest
                )
            }
            return downloaded.data
        } catch {
            if inFlight[url]?.id == requestID { inFlight[url] = nil }
            throw error
        }
    }

    func removeAllCachedImages() {
        generation += 1
        inFlight.removeAll()
        cache.removeAllCachedResponses()
    }

    private static func isValidImage(_ data: Data, response: URLResponse) -> Bool {
        guard !data.isEmpty, data.count <= maximumImageBytes,
              response.mimeType?.lowercased().hasPrefix("image/") == true else { return false }
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) { return false }
        return NSImage(data: data) != nil
    }

    private static func downloadImage(using session: URLSession, request: URLRequest) async throws -> DownloadedImage {
        let (bytes, response) = try await session.bytes(for: request)
        guard response.mimeType?.lowercased().hasPrefix("image/") == true else {
            throw ImageCacheError.invalidResponse
        }
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw ImageCacheError.invalidResponse
        }
        let expectedLength = response.expectedContentLength
        guard expectedLength < 0 || expectedLength <= Int64(maximumImageBytes) else {
            throw ImageCacheError.responseTooLarge
        }

        var data = Data()
        if expectedLength > 0 { data.reserveCapacity(Int(expectedLength)) }
        for try await byte in bytes {
            guard data.count < maximumImageBytes else {
                throw ImageCacheError.responseTooLarge
            }
            data.append(byte)
        }
        guard isValidImage(data, response: response) else {
            throw ImageCacheError.invalidResponse
        }
        return DownloadedImage(data: data, response: response)
    }

    private struct InFlightRequest {
        let id: UUID
        let generation: Int
        let task: Task<DownloadedImage, Error>
    }

    private struct DownloadedImage: @unchecked Sendable {
        let data: Data
        let response: URLResponse
    }

    private enum ImageCacheError: Error {
        case invalidResponse, responseTooLarge
    }
}

struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    private let content: (AsyncImagePhase) -> Content
    @StateObject private var loader = CachedImageLoader()

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(loader.phase)
            .task(id: url) {
                await loader.load(url)
            }
    }
}

@MainActor
private final class CachedImageLoader: ObservableObject {
    @Published private(set) var phase: AsyncImagePhase = .empty

    func load(_ url: URL?) async {
        phase = .empty
        guard let url else { return }
        do {
            let data = try await ImageCacheStore.shared.data(for: url)
            try Task.checkCancellation()
            guard let image = NSImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            phase = .success(Image(nsImage: image))
        } catch is CancellationError {
            return
        } catch {
            phase = .failure(error)
        }
    }
}
