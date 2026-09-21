import XCTest
@testable import Yootube

final class ImageCacheTests: XCTestCase {
    func testConfiguredDiskLimitIs300Megabytes() {
        XCTAssertEqual(ImageCacheStore.diskCapacityBytes, 300 * 1024 * 1024)
    }

    func testStoredImageCanBeReadAndClearedWithoutNetworkAccess() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 1024 * 1024, directory: directory)
        let store = ImageCacheStore(cache: cache, session: URLSession(configuration: .ephemeral))
        let url = try XCTUnwrap(URL(string: "https://invalid.example/thumbnail.png"))
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        let data = try XCTUnwrap(Self.pngData())
        let response = URLResponse(
            url: url,
            mimeType: "image/png",
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        cache.storeCachedResponse(
            CachedURLResponse(response: response, data: data, storagePolicy: .allowed),
            for: request
        )

        let cachedData = try await store.data(for: url)
        XCTAssertEqual(cachedData, data)
        await store.removeAllCachedImages()
        XCTAssertNil(cache.cachedResponse(for: request))
    }

    func testConcurrentRequestsShareOneDownload() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 1024 * 1024, directory: directory)
        let session = Self.stubSession()
        let store = ImageCacheStore(cache: cache, session: session)
        let data = try XCTUnwrap(Self.pngData())
        let control = ImageCacheURLProtocol.prepare(data: data)
        let url = try XCTUnwrap(URL(string: "https://cache.test/shared.png"))

        let first = Task { try await store.data(for: url) }
        XCTAssertEqual(control.started.wait(timeout: .now() + 3), .success)
        let second = Task { try await store.data(for: url) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(ImageCacheURLProtocol.requestCount, 1)
        control.release.signal()

        let firstData = try await first.value
        let secondData = try await second.value
        XCTAssertEqual(firstData, data)
        XCTAssertEqual(secondData, data)
    }

    func testClearPreventsAnEarlierRequestFromWritingAfterward() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 1024 * 1024, directory: directory)
        let store = ImageCacheStore(cache: cache, session: Self.stubSession())
        let control = ImageCacheURLProtocol.prepare(data: try XCTUnwrap(Self.pngData()))
        let url = try XCTUnwrap(URL(string: "https://cache.test/cleared.png"))
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

        let pending = Task { try await store.data(for: url) }
        XCTAssertEqual(control.started.wait(timeout: .now() + 3), .success)
        await store.removeAllCachedImages()
        control.release.signal()
        _ = try await pending.value

        XCTAssertNil(cache.cachedResponse(for: request))
    }

    func testOversizedResponseIsRejectedWithoutCaching() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 1024 * 1024, directory: directory)
        let store = ImageCacheStore(cache: cache, session: Self.stubSession())
        let control = ImageCacheURLProtocol.prepare(
            data: try XCTUnwrap(Self.pngData()),
            advertisedLength: 25 * 1024 * 1024 + 1
        )
        let url = try XCTUnwrap(URL(string: "https://cache.test/oversized.png"))
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        let pending = Task { try await store.data(for: url) }
        XCTAssertEqual(control.started.wait(timeout: .now() + 3), .success)
        control.release.signal()

        do {
            _ = try await pending.value
            XCTFail("Oversized images must be rejected")
        } catch {}
        XCTAssertNil(cache.cachedResponse(for: request))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("YootubeImageCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageCacheURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func pngData() -> Data? {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlO89sAAAAASUVORK5CYII=")
    }
}

private final class ImageCacheURLProtocol: URLProtocol, @unchecked Sendable {
    struct Control {
        let started: DispatchSemaphore
        let release: DispatchSemaphore
    }

    private static let state = State()
    static var requestCount: Int { state.requestCount }

    static func prepare(data: Data, advertisedLength: Int? = nil) -> Control {
        state.prepare(data: data, advertisedLength: advertisedLength)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = Self.state.beginRequest()
        DispatchQueue.global().async { [weak self] in
            response.release.wait()
            guard let self, let url = self.request.url,
                  let http = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "image/png",
                        "Content-Length": "\(response.advertisedLength)"
                    ]
                  ) else { return }
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var advertisedLength = 0
        private var started = DispatchSemaphore(value: 0)
        private var release = DispatchSemaphore(value: 0)
        private var count = 0

        var requestCount: Int {
            lock.withLock { count }
        }

        func prepare(data: Data, advertisedLength: Int?) -> Control {
            lock.withLock {
                self.data = data
                self.advertisedLength = advertisedLength ?? data.count
                started = DispatchSemaphore(value: 0)
                release = DispatchSemaphore(value: 0)
                count = 0
                return Control(started: started, release: release)
            }
        }

        func beginRequest() -> (data: Data, advertisedLength: Int, release: DispatchSemaphore) {
            lock.withLock {
                count += 1
                started.signal()
                return (data, advertisedLength, release)
            }
        }
    }
}
