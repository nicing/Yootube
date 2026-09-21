import Foundation

struct LocalDataArchive: Codable, Equatable {
    let formatVersion: Int
    let exportedAt: Date
    let playlists: [FavoriteFolder]
    let subscriptions: [ChannelSubscription]
    let recentlyWatched: [WatchEntry]
}

enum LocalDataImportMode {
    case merge
    case replace
}

enum LocalDataTransfer {
    static let maximumArchiveSize = 20 * 1024 * 1024

    @MainActor
    static func makeArchive(favorites: FavoritesStore,
                            subscriptions: ChannelSubscriptionStore,
                            history: WatchHistory) throws -> LocalDataArchive {
        guard favorites.isLoaded, subscriptions.isLoaded else { throw TransferError.localDataUnavailable }
        let archive = LocalDataArchive(formatVersion: 1, exportedAt: Date(),
                                       playlists: favorites.folders,
                                       subscriptions: subscriptions.channels,
                                       recentlyWatched: history.entries)
        try validate(archive)
        return archive
    }

    static func encode(_ archive: LocalDataArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    static func decode(contentsOf url: URL) throws -> LocalDataArchive {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size > 0, size <= maximumArchiveSize else { throw TransferError.invalidArchive }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(LocalDataArchive.self, from: data)
        try validate(archive)
        return archive
    }

    static func validate(_ archive: LocalDataArchive) throws {
        guard archive.formatVersion == 1, archive.playlists.count <= 500,
              archive.subscriptions.count <= 10_000 else { throw TransferError.invalidArchive }
        do {
            try FavoritesStore.validate(archive.playlists)
            try ChannelSubscriptionStore.validate(archive.subscriptions)
            guard WatchHistory.isValid(archive.recentlyWatched) else { throw TransferError.invalidArchive }
        } catch {
            throw TransferError.invalidArchive
        }
    }

    @MainActor
    static func hasUserData(favorites: FavoritesStore,
                            subscriptions: ChannelSubscriptionStore,
                            history: WatchHistory) -> Bool {
        let pristinePlaylists = favorites.folders.count == 2 &&
            favorites.folders.map(\.name) == ["Watch Later", "Favorite"] &&
            favorites.folders.allSatisfy {
                $0.videos.isEmpty && $0.sourcePlaylistID == nil && $0.iconName == nil && $0.colorHex == nil
            }
        return !pristinePlaylists || !subscriptions.channels.isEmpty || !history.entries.isEmpty
    }

    @MainActor
    @discardableResult
    static func apply(_ imported: LocalDataArchive,
                      mode: LocalDataImportMode,
                      favorites: FavoritesStore,
                      subscriptions: ChannelSubscriptionStore,
                      history: WatchHistory,
                      backupDirectory: URL) throws -> URL {
        try validate(imported)
        let current = try makeArchive(favorites: favorites, subscriptions: subscriptions, history: history)
        let target: LocalDataArchive
        switch mode {
        case .merge: target = merged(current: current, imported: imported)
        case .replace: target = imported
        }
        try validate(target)

        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backupURL = backupDirectory.appendingPathComponent("Yootube-before-import-\(UUID().uuidString).json")
        try encode(current).write(to: backupURL, options: .atomic)

        guard favorites.replaceAll(with: target.playlists) else { throw TransferError.writeFailed }
        guard subscriptions.replaceAll(with: target.subscriptions) else {
            _ = favorites.replaceAll(with: current.playlists)
            throw TransferError.writeFailed
        }
        guard history.replaceAll(with: target.recentlyWatched) else {
            _ = history.replaceAll(with: current.recentlyWatched)
            _ = subscriptions.replaceAll(with: current.subscriptions)
            _ = favorites.replaceAll(with: current.playlists)
            throw TransferError.writeFailed
        }
        return backupURL
    }

    static func merged(current: LocalDataArchive, imported: LocalDataArchive) -> LocalDataArchive {
        LocalDataArchive(formatVersion: 1, exportedAt: Date(),
                         playlists: mergePlaylists(current.playlists, imported.playlists),
                         subscriptions: mergeSubscriptions(current.subscriptions, imported.subscriptions),
                         recentlyWatched: mergeHistory(current.recentlyWatched, imported.recentlyWatched))
    }

    private static func mergePlaylists(_ current: [FavoriteFolder], _ imported: [FavoriteFolder]) -> [FavoriteFolder] {
        var result = current
        for folder in imported {
            let match = result.firstIndex {
                $0.id == folder.id ||
                    ($0.sourcePlaylistID != nil && $0.sourcePlaylistID == folder.sourcePlaylistID) ||
                    $0.name.localizedCaseInsensitiveCompare(folder.name) == .orderedSame
            }
            guard let index = match else { result.append(folder); continue }
            var videoIDs = Set(result[index].videos.map(\.id))
            result[index].videos.append(contentsOf: folder.videos.filter { videoIDs.insert($0.id).inserted })
            if result[index].iconName == nil { result[index].iconName = folder.iconName }
            if result[index].colorHex == nil { result[index].colorHex = folder.colorHex }
        }
        return result
    }

    private static func mergeSubscriptions(_ current: [ChannelSubscription],
                                           _ imported: [ChannelSubscription]) -> [ChannelSubscription] {
        var byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for channel in imported {
            if let existing = byID[channel.id], existing.subscribedAt >= channel.subscribedAt { continue }
            byID[channel.id] = channel
        }
        return byID.values.sorted { $0.subscribedAt > $1.subscribedAt }
    }

    private static func mergeHistory(_ current: [WatchEntry], _ imported: [WatchEntry]) -> [WatchEntry] {
        var byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for entry in imported {
            if let existing = byID[entry.id], existing.watchedAt >= entry.watchedAt { continue }
            byID[entry.id] = entry
        }
        return Array(byID.values.sorted { $0.watchedAt > $1.watchedAt }.prefix(30))
    }

    enum TransferError: LocalizedError {
        case invalidArchive
        case localDataUnavailable
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .invalidArchive: L10n.t("备份文件无效或版本不受支持，本地数据未修改。")
            case .localDataUnavailable: L10n.t("无法读取当前本地数据，原文件已保留。")
            case .writeFailed: L10n.t("导入失败，已尝试恢复导入前的数据。")
            }
        }
    }
}

extension Notification.Name {
    static let localDataImported = Notification.Name("Yootube.localDataImported")
}
