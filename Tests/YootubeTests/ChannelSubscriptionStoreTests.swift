import XCTest
@testable import Yootube

final class ChannelSubscriptionStoreTests: XCTestCase {
    @MainActor
    func testSubscriptionTogglePersistsLocally() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ChannelSubscriptionStore(fileURL: file)
        XCTAssertTrue(store.isLoaded)
        XCTAssertTrue(store.channels.isEmpty)

        let channel = try nativeChannel()
        XCTAssertTrue(store.toggle(channel))
        XCTAssertTrue(store.contains(channel.authorId))
        XCTAssertEqual(store.channels.first?.name, channel.author)
        XCTAssertEqual(ChannelSubscriptionStore(fileURL: file).channels, store.channels)

        XCTAssertTrue(store.toggle(channel))
        XCTAssertFalse(store.contains(channel.authorId))
        XCTAssertTrue(ChannelSubscriptionStore(fileURL: file).channels.isEmpty)
    }

    @MainActor
    func testCorruptSubscriptionFileIsPreserved() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("incomplete JSON".utf8)
        try original.write(to: file)

        let store = ChannelSubscriptionStore(fileURL: file)
        XCTAssertFalse(store.isLoaded)
        XCTAssertFalse(store.toggle(try nativeChannel()))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    @MainActor
    func testWriteFailureDoesNotChangeVisibleSubscriptions() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ChannelSubscriptionStore(fileURL: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)

        XCTAssertFalse(store.toggle(try nativeChannel()))
        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    private func nativeChannel() throws -> NativeChannel {
        try JSONDecoder().decode(NativeChannel.self, from: Data(#"""
        {
            "author":"Example Channel",
            "authorId":"UCwrVwiJllwhJUKXKmjLcckQ",
            "authorThumbnails":[{"url":"https://yt3.ggpht.com/example","width":88,"height":88}],
            "latestVideos":[]
        }
        """#.utf8))
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("YootubeSubscriptionTests-\(UUID().uuidString)")
            .appendingPathComponent("subscriptions.json")
    }
}
