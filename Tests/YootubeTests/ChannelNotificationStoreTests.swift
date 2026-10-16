import XCTest
@testable import Yootube

final class ChannelNotificationStoreTests: XCTestCase {
    @MainActor
    func testFirstCheckCreatesBaselineAndNextCheckAddsOnlyNewVideos() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var channel = try nativeChannel(videoIDs: ["AAAAAAAAAAA"])
        let store = ChannelNotificationStore(fileURL: file) { _ in channel }
        let subscription = ChannelSubscription(id: "UCexample", name: "Example", avatarSource: nil,
                                               subscribedAt: Date())

        await store.checkForUpdates(in: [subscription], minimumInterval: 0,
                                    deliverSystemNotifications: false)
        XCTAssertTrue(store.notifications.isEmpty)

        channel = try nativeChannel(videoIDs: ["BBBBBBBBBBB", "AAAAAAAAAAA"])
        await store.checkForUpdates(in: [subscription], minimumInterval: 0,
                                    deliverSystemNotifications: false)

        XCTAssertEqual(store.notifications.map(\.videoID), ["BBBBBBBBBBB"])
        XCTAssertEqual(store.unreadCount, 1)

        await store.checkForUpdates(in: [subscription], minimumInterval: 0,
                                    deliverSystemNotifications: false)
        XCTAssertEqual(store.notifications.count, 1)
        XCTAssertEqual(ChannelNotificationStore(fileURL: file, fetchChannel: { _ in channel }).notifications,
                       store.notifications)
    }

    @MainActor
    func testReadStatePersists() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var channel = try nativeChannel(videoIDs: ["AAAAAAAAAAA"])
        let store = ChannelNotificationStore(fileURL: file) { _ in channel }
        let subscription = ChannelSubscription(id: "UCexample", name: "Example", avatarSource: nil,
                                               subscribedAt: Date())
        await store.checkForUpdates(in: [subscription], minimumInterval: 0,
                                    deliverSystemNotifications: false)
        channel = try nativeChannel(videoIDs: ["BBBBBBBBBBB", "AAAAAAAAAAA"])
        await store.checkForUpdates(in: [subscription], minimumInterval: 0,
                                    deliverSystemNotifications: false)

        store.markAllRead()

        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertTrue(ChannelNotificationStore(fileURL: file, fetchChannel: { _ in channel })
            .notifications.allSatisfy(\.isRead))
    }

    @MainActor
    func testNotificationsAreSortedByNewestPublicationTime() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let now = Int(Date().timeIntervalSince1970)
        var channel = try nativeChannel(videoIDs: ["AAAAAAAAAAA"],
                                        publishedByID: ["AAAAAAAAAAA": now - 7_200])
        let store = ChannelNotificationStore(fileURL: file) { _ in channel }
        let subscription = ChannelSubscription(id: "UCexample", name: "Example", avatarSource: nil,
                                               subscribedAt: Date())
        await store.checkForUpdates(in: [subscription], minimumInterval: 0,
                                    deliverSystemNotifications: false)

        channel = try nativeChannel(
            videoIDs: ["BBBBBBBBBBB", "CCCCCCCCCCC", "DDDDDDDDDDD", "AAAAAAAAAAA"],
            publishedByID: [
                "BBBBBBBBBBB": now - 3_600,
                "CCCCCCCCCCC": now - 60,
                "DDDDDDDDDDD": now - 180,
                "AAAAAAAAAAA": now - 7_200
            ]
        )
        await store.checkForUpdates(in: [subscription], minimumInterval: 0,
                                    deliverSystemNotifications: false)

        XCTAssertEqual(store.notifications.map(\.videoID),
                       ["CCCCCCCCCCC", "DDDDDDDDDDD", "BBBBBBBBBBB"])
    }

    func testLegacyRelativePublicationTextStillSortsNewestFirst() {
        let detectedAt = Date()
        let updates = [("old", "54 minutes ago"), ("new", "1 minute ago"), ("middle", "3 minutes ago")]
            .map { id, publishedText in
                ChannelUpdateNotification(id: id, videoID: "AAAAAAAAAAA", videoTitle: id,
                                          channelID: "UCexample", channelName: "Example",
                                          publishedAt: nil, publishedText: publishedText,
                                          detectedAt: detectedAt, isRead: false)
            }

        let reference = Date()
        XCTAssertEqual(updates.sorted {
            $0.publicationSortDate(relativeTo: reference) >
                $1.publicationSortDate(relativeTo: reference)
        }.map(\.id),
                       ["new", "middle", "old"])
    }

    @MainActor
    func testUnsubscribedPeriodDoesNotCreateNotificationsAfterResubscribing() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var channel = try nativeChannel(videoIDs: ["AAAAAAAAAAA"])
        let store = ChannelNotificationStore(fileURL: file) { _ in channel }
        let subscription = ChannelSubscription(id: "UCexample", name: "Example", avatarSource: nil,
                                               subscribedAt: Date())
        await store.checkForUpdates(in: [subscription], minimumInterval: 0,
                                    deliverSystemNotifications: false)

        await store.checkForUpdates(in: [], minimumInterval: .greatestFiniteMagnitude,
                                    deliverSystemNotifications: false)
        channel = try nativeChannel(videoIDs: ["BBBBBBBBBBB", "AAAAAAAAAAA"])
        await store.checkForUpdates(in: [subscription], minimumInterval: .greatestFiniteMagnitude,
                                    deliverSystemNotifications: false)

        XCTAssertTrue(store.notifications.isEmpty)
    }

    @MainActor
    func testCorruptFileIsPreserved() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let original = Data("invalid JSON".utf8)
        try original.write(to: file)

        let store = ChannelNotificationStore(fileURL: file, fetchChannel: { _ in
            throw VideoAPI.APIError.unavailable
        })

        XCTAssertFalse(store.isLoaded)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    private func nativeChannel(videoIDs: [String], publishedByID: [String: Int] = [:]) throws -> NativeChannel {
        NativeChannel(
            author: "Example Channel",
            authorId: "UCexample",
            authorVerified: nil,
            authorBanners: nil,
            authorThumbnails: nil,
            subCount: nil,
            totalViews: nil,
            description: nil,
            latestVideos: videoIDs.map { id in
                NativeVideo(videoId: id, title: "Video \(id)", author: nil, authorId: nil,
                            viewCount: nil, viewCountText: nil, published: publishedByID[id],
                            publishedText: "now", lengthSeconds: nil)
            }
        )
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("YootubeNotificationTests-\(UUID().uuidString)")
            .appendingPathComponent("channel-notifications.json")
    }
}
