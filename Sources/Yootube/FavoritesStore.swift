import Foundation

struct FavoriteFolderIconOption: Identifiable, Sendable {
    let id: String
    let title: String
}

struct FavoriteFolderColorOption: Identifiable, Sendable {
    let hex: String
    let title: String
    let usesDarkCheckmark: Bool
    var id: String { hex }
}

enum FavoriteFolderStyle {
    private static let legacyColorMap = [
        "#202124": "#1D1D1F",
        "#5B5B66": "#333333",
        "#A1A1AA": "#7A7A7A"
    ]

    static var iconOptions: [FavoriteFolderIconOption] { [
        FavoriteFolderIconOption(id: "playlist", title: L10n.t("播放列表")),
        FavoriteFolderIconOption(id: "star", title: L10n.t("星标")),
        FavoriteFolderIconOption(id: "clock", title: L10n.t("稍后观看")),
        FavoriteFolderIconOption(id: "bookmark-simple", title: L10n.t("书签")),
        FavoriteFolderIconOption(id: "play", title: L10n.t("播放")),
        FavoriteFolderIconOption(id: "video-camera", title: L10n.t("视频")),
        FavoriteFolderIconOption(id: "headphones", title: L10n.t("音乐")),
        FavoriteFolderIconOption(id: "rss", title: L10n.t("订阅")),
        FavoriteFolderIconOption(id: "folder-simple", title: L10n.t("文件夹")),
        FavoriteFolderIconOption(id: "bell", title: L10n.t("提醒")),
        FavoriteFolderIconOption(id: "globe", title: L10n.t("全球")),
        FavoriteFolderIconOption(id: "eye", title: L10n.t("观看")),
        FavoriteFolderIconOption(id: "thumbs-up", title: L10n.t("喜欢")),
        FavoriteFolderIconOption(id: "newspaper", title: L10n.t("资讯")),
        FavoriteFolderIconOption(id: "code", title: L10n.t("编程")),
        FavoriteFolderIconOption(id: "desktop", title: L10n.t("科技")),
        FavoriteFolderIconOption(id: "user", title: L10n.t("人物")),
        FavoriteFolderIconOption(id: "lock", title: L10n.t("私人"))
    ] }

    static var colorOptions: [FavoriteFolderColorOption] { [
        FavoriteFolderColorOption(hex: "#1D1D1F", title: L10n.t("黑色"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#333333", title: L10n.t("深灰"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#7A7A7A", title: L10n.t("浅灰"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#B000C0", title: L10n.t("洋红"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#6D08E8", title: L10n.t("紫色"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#2447B9", title: L10n.t("靛蓝"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#1769FF", title: L10n.t("蓝色"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#0797B6", title: L10n.t("青色"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#00867A", title: L10n.t("蓝绿"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#009C6F", title: L10n.t("翠绿"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#00C853", title: L10n.t("绿色"), usesDarkCheckmark: true),
        FavoriteFolderColorOption(hex: "#72D400", title: L10n.t("青柠"), usesDarkCheckmark: true),
        FavoriteFolderColorOption(hex: "#FFB700", title: L10n.t("黄色"), usesDarkCheckmark: true),
        FavoriteFolderColorOption(hex: "#EE7400", title: L10n.t("橙色"), usesDarkCheckmark: true),
        FavoriteFolderColorOption(hex: "#FF3D00", title: L10n.t("橙红"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#F00813", title: L10n.t("红色"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#E90075", title: L10n.t("粉红"), usesDarkCheckmark: false),
        FavoriteFolderColorOption(hex: "#FF3158", title: L10n.t("珊瑚红"), usesDarkCheckmark: false)
    ] }

    static let defaultIconName = "playlist"
    static let defaultColorHex = "#FF3158"

    static func defaultIconName(for folderName: String) -> String {
        switch folderName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "watch later": "clock"
        case "favorite", "favorites": "star"
        default: defaultIconName
        }
    }

    static func resolvedIconName(for folder: FavoriteFolder) -> String {
        folder.iconName ?? defaultIconName(for: folder.name)
    }

    static func resolvedColorHex(_ colorHex: String?) -> String? {
        guard let colorHex else { return nil }
        return legacyColorMap[colorHex.uppercased()] ?? colorHex
    }

    static func isValid(iconName: String?, colorHex: String?) -> Bool {
        (iconName == nil || iconOptions.contains { $0.id == iconName }) &&
            (colorHex == nil || colorOptions.contains { $0.hex == colorHex } ||
                legacyColorMap[colorHex?.uppercased() ?? ""] != nil)
    }
}

struct FavoriteVideo: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let author: String
    let savedAt: Date

    var url: URL? { VideoRoute.watchURL(id: id) }
    var thumbnailURL: URL {
        LocalServiceManager.invidiousURL.appendingPathComponent("vi/\(id)/mqdefault.jpg")
    }
}

@MainActor
final class FavoritesStore: ObservableObject {
    static let defaultFileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Yootube/favorites.json")

    @Published private(set) var folders: [FavoriteFolder] = []
    @Published private(set) var isLoaded = false
    @Published var errorMessage: String?
    let fileURL: URL

    init(fileURL: URL = FavoritesStore.defaultFileURL) {
        self.fileURL = fileURL
        reload()
    }

    func contains(_ id: String) -> Bool { folders.contains { $0.videos.contains { $0.id == id } } }

    func folder(_ id: UUID) -> FavoriteFolder? { folders.first { $0.id == id } }

    func reload() {
        do {
            let data = try Data(contentsOf: fileURL)
            if let document = try? JSONDecoder().decode(FavoritesDocument.self, from: data) {
                try Self.validate(document.folders)
                folders = document.folders
                isLoaded = true
                errorMessage = nil
            } else {
                let oldVideos = try JSONDecoder().decode([FavoriteVideo].self, from: data)
                let upgraded = Self.defaultFolders(videos: oldVideos)
                try Self.validate(upgraded)
                let backup = fileURL.appendingPathExtension("single-folder-backup")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try data.write(to: backup, options: .withoutOverwriting)
                }
                isLoaded = save(upgraded)
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            isLoaded = save(Self.defaultFolders())
        } catch {
            isLoaded = false
            errorMessage = L10n.t("无法读取本地收藏夹，原文件已保留。请检查文件后重新读取。\n\(fileURL.path)")
        }
    }

    func nameError(_ name: String, excluding id: UUID? = nil) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return L10n.t("请输入收藏夹名称") }
        if name.count > 80 { return L10n.t("名称不能超过 80 个字符") }
        if folders.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return L10n.t("已有同名收藏夹")
        }
        return nil
    }

    func createFolder(named name: String, iconName: String? = nil, colorHex: String? = nil) -> UUID? {
        guard isLoaded else { return nil }
        if let error = nameError(name) { errorMessage = error; return nil }
        guard FavoriteFolderStyle.isValid(iconName: iconName, colorHex: colorHex) else {
            errorMessage = L10n.t("收藏夹样式无效。")
            return nil
        }
        let folder = FavoriteFolder(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    videos: [], iconName: iconName, colorHex: colorHex)
        return save(folders + [folder]) ? folder.id : nil
    }

    func savePlaylist(sourceID: String, named name: String, videos: [FavoriteVideo]) -> UUID? {
        guard isLoaded else { return nil }
        var uniqueVideos: [FavoriteVideo] = []
        var videoIDs = Set<String>()
        for video in videos where video.url != nil && videoIDs.insert(video.id).inserted {
            uniqueVideos.append(video)
        }
        guard !uniqueVideos.isEmpty else {
            errorMessage = L10n.t("播放列表中没有可保存的视频。")
            return nil
        }

        var updated = folders
        if let index = updated.firstIndex(where: { $0.sourcePlaylistID == sourceID }) {
            let importedIDs = Set(uniqueVideos.map(\.id))
            let preserved = updated[index].videos.filter { !importedIDs.contains($0.id) }
            updated[index].videos = uniqueVideos + preserved
            return save(updated) ? updated[index].id : nil
        }

        let baseName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let fallback = baseName.isEmpty ? "YouTube Playlist" : baseName
        var availableName = fallback
        var suffix = 2
        while nameError(availableName) != nil {
            let ending = " (\(suffix))"
            availableName = String(fallback.prefix(max(1, 80 - ending.count))) + ending
            suffix += 1
        }
        let folder = FavoriteFolder(id: UUID(), name: availableName, videos: uniqueVideos,
                                    sourcePlaylistID: sourceID)
        return save(updated + [folder]) ? folder.id : nil
    }

    func renameFolder(_ id: UUID, to name: String) -> Bool {
        guard let folder = folder(id) else { return false }
        return updateFolder(id, name: name, iconName: folder.iconName, colorHex: folder.colorHex)
    }

    func updateFolder(_ id: UUID, name: String, iconName: String?, colorHex: String?) -> Bool {
        guard isLoaded, let index = folders.firstIndex(where: { $0.id == id }) else { return false }
        if let error = nameError(name, excluding: id) { errorMessage = error; return false }
        guard FavoriteFolderStyle.isValid(iconName: iconName, colorHex: colorHex) else {
            errorMessage = L10n.t("收藏夹样式无效。")
            return false
        }
        var updated = folders
        updated[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated[index].iconName = iconName
        updated[index].colorHex = colorHex
        return save(updated)
    }

    @discardableResult
    func deleteFolder(_ id: UUID) -> Bool {
        guard isLoaded, folder(id) != nil else { return false }
        return save(folders.filter { $0.id != id })
    }

    @discardableResult
    func moveFolder(_ sourceID: UUID, relativeTo targetID: UUID, placeAfter: Bool) -> Bool {
        guard isLoaded,
              let sourceIndex = folders.firstIndex(where: { $0.id == sourceID }),
              folders.contains(where: { $0.id == targetID }) else { return false }
        guard sourceID != targetID else { return true }

        var updated = folders
        let source = updated.remove(at: sourceIndex)
        guard let targetIndex = updated.firstIndex(where: { $0.id == targetID }) else { return false }
        updated.insert(source, at: targetIndex + (placeAfter ? 1 : 0))
        return updated == folders || save(updated)
    }

    @discardableResult
    func add(_ video: FavoriteVideo, to folderID: UUID) -> Bool {
        let title = video.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = video.author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLoaded, video.url != nil, !title.isEmpty, title.count <= 500, author.count <= 200,
              let index = folders.firstIndex(where: { $0.id == folderID }) else { return false }
        if folders[index].videos.contains(where: { $0.id == video.id }) { return true }

        var updated = folders
        updated[index].videos.insert(FavoriteVideo(id: video.id, title: title, author: author,
                                                   savedAt: video.savedAt), at: 0)
        return save(updated)
    }

    @discardableResult
    func setMembership(for video: FavoriteVideo, folderIDs: Set<UUID>) -> Bool {
        guard isLoaded, video.url != nil, folderIDs.isSubset(of: Set(folders.map(\.id))) else { return false }
        var updated = folders
        for index in updated.indices {
            if folderIDs.contains(updated[index].id) {
                if !updated[index].videos.contains(where: { $0.id == video.id }) {
                    updated[index].videos.insert(video, at: 0)
                }
            } else {
                updated[index].videos.removeAll { $0.id == video.id }
            }
        }
        return save(updated)
    }

    func remove(videoID: String, from folderID: UUID) {
        guard isLoaded, let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        var updated = folders
        updated[index].videos.removeAll { $0.id == videoID }
        save(updated)
    }

    @discardableResult
    func replaceAll(with imported: [FavoriteFolder]) -> Bool {
        guard isLoaded else { return false }
        do {
            try Self.validate(imported)
            return save(imported)
        } catch {
            errorMessage = L10n.t("备份中的收藏夹数据无效，未修改本地数据。")
            return false
        }
    }

    private static func defaultFolders(videos: [FavoriteVideo] = []) -> [FavoriteFolder] {
        [FavoriteFolder(id: UUID(), name: "Watch Later", videos: []),
         FavoriteFolder(id: UUID(), name: "Favorite", videos: videos.sorted { $0.savedAt > $1.savedAt })]
    }

    nonisolated static func validate(_ folders: [FavoriteFolder]) throws {
        var folderIDs = Set<UUID>()
        var folderNames = Set<String>()
        for folder in folders {
            var videoIDs = Set<String>()
            let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard folderIDs.insert(folder.id).inserted, folderNames.insert(name.lowercased()).inserted,
                  !name.isEmpty, name.count <= 80,
                  FavoriteFolderStyle.isValid(iconName: folder.iconName, colorHex: folder.colorHex),
                  folder.videos.allSatisfy({ $0.url != nil && videoIDs.insert($0.id).inserted }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }

    @discardableResult
    private func save(_ updated: [FavoriteFolder]) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(FavoritesDocument(folders: updated))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            folders = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = L10n.t("收藏夹保存失败，此次更改未生效。请检查磁盘空间和文件权限后重试。")
            return false
        }
    }
}

struct FavoriteFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var videos: [FavoriteVideo]
    var sourcePlaylistID: String?
    var iconName: String?
    var colorHex: String?

    init(id: UUID, name: String, videos: [FavoriteVideo], sourcePlaylistID: String? = nil,
         iconName: String? = nil, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.videos = videos
        self.sourcePlaylistID = sourcePlaylistID
        self.iconName = iconName
        self.colorHex = colorHex
    }
}

private struct FavoritesDocument: Codable {
    let folders: [FavoriteFolder]
}
