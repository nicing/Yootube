import Foundation
import XCTest
@testable import Yootube

@MainActor
final class VideoCacheTests: XCTestCase {
    func testCachedVideoCanOpenBeforeTheLocalServiceIsReady() throws {
        let cachedID = "sZSlTDlo0Ag"
        let cachedURL = try XCTUnwrap(VideoRoute.watchURL(id: cachedID))
        let uncachedURL = try XCTUnwrap(VideoRoute.watchURL(id: "4Ui09XbYf1A"))
        let searchURL = try XCTUnwrap(URL(string: "http://127.0.0.1:38473/search?q=test"))

        XCTAssertTrue(canOpenPageImmediately(
            cachedURL, serviceReady: false, cachedVideoIDs: [cachedID]
        ))
        XCTAssertFalse(canOpenPageImmediately(
            uncachedURL, serviceReady: false, cachedVideoIDs: [cachedID]
        ))
        XCTAssertFalse(canOpenPageImmediately(
            searchURL, serviceReady: false, cachedVideoIDs: [cachedID]
        ))
        XCTAssertTrue(canOpenPageImmediately(
            searchURL, serviceReady: true, cachedVideoIDs: []
        ))
    }

    func testRangedDownloadResumesWhenAProxyResponseEndsEarly() async throws {
        let payload = Data((0..<10).map(UInt8.init))
        VideoCacheURLProtocol.prepare(payload: payload, truncatesFirstResponse: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VideoCacheURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let destination = temporaryDirectory().appendingPathComponent("video.mp4")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        try await VideoCacheDownloader.download(
            URL(string: "https://cache.test/video.mp4")!,
            to: destination,
            session: session,
            expectedByteCount: Int64(payload.count),
            segmentByteCount: 4
        )

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(VideoCacheURLProtocol.ranges, ["bytes=0-3", "bytes=2-5", "bytes=6-9"])
    }

    func testValidEntryLoadsAndBuildsARestrictedPlayerPageURL() throws {
        let root = temporaryDirectory()
        let id = "sZSlTDlo0Ag"
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0, 1, 2]).write(to: directory.appendingPathComponent("video.mp4"))
        try "<video>".write(to: directory.appendingPathComponent("player.html"), atomically: true, encoding: .utf8)
        let entry = VideoCacheEntry(
            schemaVersion: VideoCacheEntry.currentSchemaVersion,
            videoID: id,
            title: "Cached title",
            author: "Channel",
            authorID: "UCtest",
            qualityHeight: 1080,
            cachedAt: Date(timeIntervalSince1970: 1),
            byteCount: 3,
            captions: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entry).write(to: directory.appendingPathComponent("manifest.json"))

        let store = VideoCacheStore(rootDirectory: root, session: .shared)
        XCTAssertEqual(store.entry(for: id), entry)
        XCTAssertEqual(store.totalByteCount, 3)
        XCTAssertEqual(store.entry(for: id)?.basicMetadata.title, "Cached title")
        let page = try XCTUnwrap(store.playerPageURL(for: id, startValue: "1m30s"))
        XCTAssertEqual(page.fragment, "t=1m30s")
        XCTAssertTrue(store.isPlayerPage(page, videoID: id))
        XCTAssertFalse(store.isPlayerPage(directory.appendingPathComponent("video.mp4"), videoID: id))
        XCTAssertEqual(store.videoFileURL(for: id), directory.appendingPathComponent("video.mp4"))
        XCTAssertNil(store.videoFileURL(for: "not-cached"))
    }

    func testCorruptEntryIsIgnoredAndPreserved() throws {
        let root = temporaryDirectory()
        let directory = root.appendingPathComponent("sZSlTDlo0Ag", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = directory.appendingPathComponent("manifest.json")
        try Data("not-json".utf8).write(to: manifest)

        let store = VideoCacheStore(rootDirectory: root, session: .shared)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: manifest), Data("not-json".utf8))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("YootubeVideoCacheTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private final class VideoCacheURLProtocol: URLProtocol, @unchecked Sendable {
    private static let state = State()

    static var ranges: [String] { state.ranges }

    static func prepare(payload: Data, truncatesFirstResponse: Bool) {
        state.prepare(payload: payload, truncatesFirstResponse: truncatesFirstResponse)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = Self.state.response(for: request.value(forHTTPHeaderField: "Range")),
              let http = HTTPURLResponse(
                url: url,
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Range": response.contentRange]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var payload = Data()
        private var shouldTruncateFirst = false
        private var requestedRanges: [String] = []

        var ranges: [String] { lock.withLock { requestedRanges } }

        func prepare(payload: Data, truncatesFirstResponse: Bool) {
            lock.withLock {
                self.payload = payload
                shouldTruncateFirst = truncatesFirstResponse
                requestedRanges = []
            }
        }

        func response(for header: String?) -> (data: Data, contentRange: String)? {
            lock.withLock {
                guard let header,
                      header.hasPrefix("bytes="),
                      let dash = header.firstIndex(of: "-"),
                      let start = Int(header[header.index(header.startIndex, offsetBy: 6)..<dash]),
                      let end = Int(header[header.index(after: dash)...]),
                      start >= 0, start <= end, end < payload.count else { return nil }
                requestedRanges.append(header)
                let declaredEnd = end
                let actualEnd: Int
                if shouldTruncateFirst {
                    shouldTruncateFirst = false
                    actualEnd = min(end, start + 1)
                } else {
                    actualEnd = end
                }
                return (
                    payload.subdata(in: start..<(actualEnd + 1)),
                    "bytes \(start)-\(declaredEnd)/\(payload.count)"
                )
            }
        }
    }
}
