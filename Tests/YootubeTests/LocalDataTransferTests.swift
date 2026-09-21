import XCTest
@testable import Yootube

final class LocalDataTransferTests: XCTestCase {
    func testArchiveRoundTripsAsPortableJSON() throws {
        let archive = sampleArchive()
        let file = temporaryDirectory().appendingPathComponent("backup.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LocalDataTransfer.encode(archive).write(to: file)
        XCTAssertEqual(try LocalDataTransfer.decode(contentsOf: file), archive)
    }

    func testMergeDeduplicatesPlaylistsChannelsAndHistory() throws {
        let now = Date()
        let folder = FavoriteFolder(id: UUID(), name: "学习", videos: [video("sZSlTDlo0Ag", at: now)])
        let current = LocalDataArchive(
            formatVersion: 1, exportedAt: now, playlists: [folder],
            subscriptions: [channel("UCcurrent", at: now), channel("UCshared", at: now)],
            recentlyWatched: [entry("sZSlTDlo0Ag", at: now)])
        let imported = LocalDataArchive(
            formatVersion: 1, exportedAt: now, playlists: [
                FavoriteFolder(id: UUID(), name: "学习", videos: [video("dQw4w9WgXcQ", at: now)],
                               iconName: "star", colorHex: "#FFB700")
            ],
            subscriptions: [channel("UCshared", at: now.addingTimeInterval(10))],
            recentlyWatched: [entry("sZSlTDlo0Ag", at: now.addingTimeInterval(10)),
                              entry("dQw4w9WgXcQ", at: now)])

        let merged = LocalDataTransfer.merged(current: current, imported: imported)
        XCTAssertEqual(merged.playlists.count, 1)
        XCTAssertEqual(merged.playlists[0].videos.map(\.id), ["sZSlTDlo0Ag", "dQw4w9WgXcQ"])
        XCTAssertEqual(merged.playlists[0].iconName, "star")
        XCTAssertEqual(merged.playlists[0].colorHex, "#FFB700")
        XCTAssertEqual(Set(merged.subscriptions.map(\.id)), ["UCcurrent", "UCshared"])
        XCTAssertEqual(merged.subscriptions.first(where: { $0.id == "UCshared" })?.subscribedAt,
                       now.addingTimeInterval(10))
        XCTAssertEqual(merged.recentlyWatched.map(\.id), ["sZSlTDlo0Ag", "dQw4w9WgXcQ"])
        XCTAssertEqual(merged.recentlyWatched[0].watchedAt, now.addingTimeInterval(10))
    }

    @MainActor
    func testReplaceCreatesRecoveryBackupAndUpdatesEveryStore() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultsName = "YootubeTransferTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let favorites = FavoritesStore(fileURL: root.appendingPathComponent("favorites.json"))
        let subscriptions = ChannelSubscriptionStore(fileURL: root.appendingPathComponent("subscriptions.json"))
        let history = WatchHistory(defaults: defaults)
        history.record(id: "sZSlTDlo0Ag", title: "Before")
        let before = try LocalDataTransfer.makeArchive(
            favorites: favorites, subscriptions: subscriptions, history: history)
        let imported = sampleArchive()

        let backup = try LocalDataTransfer.apply(
            imported, mode: .replace, favorites: favorites,
            subscriptions: subscriptions, history: history,
            backupDirectory: root.appendingPathComponent("Backups"))

        XCTAssertEqual(favorites.folders, imported.playlists)
        XCTAssertEqual(subscriptions.channels, imported.subscriptions)
        XCTAssertEqual(history.entries, imported.recentlyWatched)
        XCTAssertEqual(try LocalDataTransfer.decode(contentsOf: backup).playlists, before.playlists)
        XCTAssertEqual(WatchHistory(defaults: defaults).entries, imported.recentlyWatched)
    }

    @MainActor
    func testInvalidArchiveCannotChangeExistingData() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultsName = "YootubeTransferTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let favorites = FavoritesStore(fileURL: root.appendingPathComponent("favorites.json"))
        let subscriptions = ChannelSubscriptionStore(fileURL: root.appendingPathComponent("subscriptions.json"))
        let history = WatchHistory(defaults: defaults)
        let original = favorites.folders
        let bad = LocalDataArchive(
            formatVersion: 2, exportedAt: Date(), playlists: [], subscriptions: [], recentlyWatched: [])

        XCTAssertThrowsError(try LocalDataTransfer.apply(
            bad, mode: .replace, favorites: favorites,
            subscriptions: subscriptions, history: history,
            backupDirectory: root.appendingPathComponent("Backups")))
        XCTAssertEqual(favorites.folders, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Backups").path))
    }

    @MainActor
    func testWriteFailureRollsBackEarlierStoreChanges() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultsName = "YootubeTransferTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let favoritesURL = root.appendingPathComponent("favorites.json")
        let subscriptionsURL = root.appendingPathComponent("subscriptions.json")
        let favorites = FavoritesStore(fileURL: favoritesURL)
        let subscriptions = ChannelSubscriptionStore(fileURL: subscriptionsURL)
        let history = WatchHistory(defaults: defaults)
        let originalFolders = favorites.folders
        try FileManager.default.removeItem(at: subscriptionsURL)
        try FileManager.default.createDirectory(at: subscriptionsURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(try LocalDataTransfer.apply(
            sampleArchive(), mode: .replace, favorites: favorites,
            subscriptions: subscriptions, history: history,
            backupDirectory: root.appendingPathComponent("Backups")))
        XCTAssertEqual(favorites.folders, originalFolders)
        XCTAssertEqual(FavoritesStore(fileURL: favoritesURL).folders, originalFolders)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Backups").path))
    }

    @MainActor
    func testPristineDefaultsDoNotRequireMergeChoice() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultsName = "YootubeTransferTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let favorites = FavoritesStore(fileURL: root.appendingPathComponent("favorites.json"))
        let subscriptions = ChannelSubscriptionStore(fileURL: root.appendingPathComponent("subscriptions.json"))
        let history = WatchHistory(defaults: defaults)

        XCTAssertFalse(LocalDataTransfer.hasUserData(
            favorites: favorites, subscriptions: subscriptions, history: history))
        let folder = try XCTUnwrap(favorites.folders.first)
        XCTAssertTrue(favorites.updateFolder(folder.id, name: folder.name,
                                             iconName: "clock", colorHex: "#1769FF"))
        XCTAssertTrue(LocalDataTransfer.hasUserData(
            favorites: favorites, subscriptions: subscriptions, history: history))
    }

    private func sampleArchive() -> LocalDataArchive {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return LocalDataArchive(
            formatVersion: 1, exportedAt: date,
            playlists: [FavoriteFolder(id: UUID(uuidString: "E13D60D8-5C59-4DB4-BB40-C217A17FBC34")!,
                                       name: "Music", videos: [video("sZSlTDlo0Ag", at: date)])],
            subscriptions: [channel("UCsample", at: date)],
            recentlyWatched: [entry("sZSlTDlo0Ag", at: date)])
    }

    private func video(_ id: String, at date: Date) -> FavoriteVideo {
        FavoriteVideo(id: id, title: "Video \(id)", author: "Channel", savedAt: date)
    }

    private func channel(_ id: String, at date: Date) -> ChannelSubscription {
        ChannelSubscription(id: id, name: "Channel \(id)", avatarSource: nil, subscribedAt: date)
    }

    private func entry(_ id: String, at date: Date) -> WatchEntry {
        WatchEntry(id: id, title: "Watched \(id)", watchedAt: date)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("YootubeTransferTests-\(UUID().uuidString)")
    }
}
