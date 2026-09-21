import AVFoundation
import XCTest
@testable import Yootube

@MainActor
final class VideoCacheIntegrationTests: XCTestCase {
    func testCachesAReal1080pVideoWithAudioAndReloadsIt() async throws {
        guard ProcessInfo.processInfo.environment["YOOTUBE_CACHE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set YOOTUBE_CACHE_INTEGRATION=1 while the local service is running")
        }

        let video = try await VideoAPI.fetch(
            VideoMetadata.self,
            path: "api/v1/videos/Qey0V-UtK6U",
            query: [URLQueryItem(name: "local", value: "true")]
        )
        let option = try XCTUnwrap(video.cacheOptions.first { $0.height == 1080 })
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YootubeRealVideoCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VideoCacheStore(rootDirectory: root, session: .shared)

        store.cache(video, option: option)
        for _ in 0..<3_600 where store.isCaching(video.videoId) {
            try await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertFalse(store.isCaching(video.videoId), "The real cache operation timed out")
        XCTAssertNil(store.error(for: video.videoId))
        let entry = try XCTUnwrap(store.entry(for: video.videoId))
        XCTAssertEqual(entry.qualityHeight, 1080)

        let file = root.appendingPathComponent(video.videoId).appendingPathComponent("video.mp4")
        let asset = AVURLAsset(url: file)
        let isPlayable = try await asset.load(.isPlayable)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let audioTrack = try XCTUnwrap(audioTracks.first)
        let naturalSize = try await videoTrack.load(.naturalSize)
        XCTAssertTrue(isPlayable)
        XCTAssertGreaterThanOrEqual(naturalSize.height, 1_080)
        XCTAssertNotNil(audioTrack)

        let reloaded = VideoCacheStore(rootDirectory: root, session: .shared)
        let reloadedEntry = try XCTUnwrap(reloaded.entry(for: video.videoId))
        XCTAssertEqual(reloadedEntry.videoID, entry.videoID)
        XCTAssertEqual(reloadedEntry.qualityHeight, entry.qualityHeight)
        XCTAssertEqual(reloadedEntry.byteCount, entry.byteCount)
        XCTAssertLessThan(abs(reloadedEntry.cachedAt.timeIntervalSince(entry.cachedAt)), 1)
        XCTAssertNotNil(reloaded.playerPageURL(for: video.videoId, startValue: nil))
    }
}
