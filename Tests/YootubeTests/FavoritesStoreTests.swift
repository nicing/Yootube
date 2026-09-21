import XCTest
@testable import Yootube

final class FavoritesStoreTests: XCTestCase {
    func testLegacyGrayFolderColorsRemainReadableAndUseApplePalette() {
        XCTAssertTrue(FavoriteFolderStyle.isValid(iconName: "playlist", colorHex: "#202124"))
        XCTAssertTrue(FavoriteFolderStyle.isValid(iconName: "playlist", colorHex: "#5B5B66"))
        XCTAssertTrue(FavoriteFolderStyle.isValid(iconName: "playlist", colorHex: "#A1A1AA"))
        XCTAssertEqual(FavoriteFolderStyle.resolvedColorHex("#202124"), "#1D1D1F")
        XCTAssertEqual(FavoriteFolderStyle.resolvedColorHex("#5B5B66"), "#333333")
        XCTAssertEqual(FavoriteFolderStyle.resolvedColorHex("#A1A1AA"), "#7A7A7A")
    }

    @MainActor
    func testDefaultsCreatedOnceAndDeletedFoldersStayDeleted() {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        XCTAssertTrue(store.isLoaded)
        XCTAssertEqual(store.folders.map(\.name), ["Watch Later", "Favorite"])
        let ids = store.folders.map(\.id)
        XCTAssertEqual(FavoritesStore(fileURL: file).folders.map(\.id), ids)
        for id in ids { XCTAssertTrue(store.deleteFolder(id)) }
        XCTAssertTrue(FavoritesStore(fileURL: file).folders.isEmpty)
    }

    @MainActor
    func testCreateRenameDeleteAndNameValidation() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        let id = try XCTUnwrap(store.createFolder(named: "  学习  "))
        XCTAssertEqual(store.folder(id)?.name, "学习")
        XCTAssertNil(store.createFolder(named: " "))
        XCTAssertNil(store.createFolder(named: "favorite"))
        XCTAssertFalse(store.renameFolder(id, to: "Watch Later"))
        XCTAssertTrue(store.renameFolder(id, to: "SwiftUI 教程"))
        XCTAssertEqual(FavoritesStore(fileURL: file).folder(id)?.name, "SwiftUI 教程")
        XCTAssertTrue(store.deleteFolder(id))
        XCTAssertNil(FavoritesStore(fileURL: file).folder(id))
    }

    @MainActor
    func testFolderIconAndColorCanBeEditedAndPersisted() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        let id = try XCTUnwrap(store.createFolder(named: "课程", iconName: "headphones", colorHex: "#6D08E8"))

        XCTAssertTrue(store.updateFolder(id, name: "设计课程", iconName: "star", colorHex: "#FFB700"))
        let restored = try XCTUnwrap(FavoritesStore(fileURL: file).folder(id))
        XCTAssertEqual(restored.name, "设计课程")
        XCTAssertEqual(restored.iconName, "star")
        XCTAssertEqual(restored.colorHex, "#FFB700")

        XCTAssertFalse(store.updateFolder(id, name: "设计课程", iconName: "unknown", colorHex: "#FFB700"))
        XCTAssertEqual(store.folder(id), restored)
    }

    @MainActor
    func testMembershipAcrossFoldersIsIndependentAndPersistent() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        let ids = store.folders.map(\.id)
        let first = video("sZSlTDlo0Ag")
        XCTAssertTrue(store.setMembership(for: first, folderIDs: Set(ids)))
        XCTAssertTrue(store.setMembership(for: first, folderIDs: Set(ids)))
        XCTAssertEqual(store.folders.map { $0.videos.count }, [1, 1])
        store.remove(videoID: first.id, from: ids[0])
        XCTAssertEqual(store.folders.map { $0.videos.count }, [0, 1])
        XCTAssertTrue(store.contains(first.id))
        let restored = FavoritesStore(fileURL: file)
        XCTAssertEqual(restored.folders, store.folders)
        XCTAssertTrue(restored.deleteFolder(ids[0]))
        XCTAssertTrue(restored.contains(first.id))
        XCTAssertTrue(restored.setMembership(for: first, folderIDs: []))
        XCTAssertFalse(FavoritesStore(fileURL: file).contains(first.id))
    }

    @MainActor
    func testFoldersCanMoveBeforeAndAfterAnotherFolderAndPersist() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        let thirdID = try XCTUnwrap(store.createFolder(named: "Third"))
        let firstID = store.folders[0].id
        let secondID = store.folders[1].id

        XCTAssertTrue(store.moveFolder(thirdID, relativeTo: firstID, placeAfter: false))
        XCTAssertEqual(store.folders.map(\.id), [thirdID, firstID, secondID])
        XCTAssertTrue(store.moveFolder(thirdID, relativeTo: secondID, placeAfter: true))
        XCTAssertEqual(store.folders.map(\.id), [firstID, secondID, thirdID])
        XCTAssertEqual(FavoritesStore(fileURL: file).folders.map(\.id), [firstID, secondID, thirdID])
    }

    @MainActor
    func testMovingFolderOntoItselfDoesNotChangeOrder() {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        let original = store.folders

        XCTAssertTrue(store.moveFolder(original[0].id, relativeTo: original[0].id, placeAfter: true))
        XCTAssertEqual(store.folders, original)
    }

    @MainActor
    func testAddingVideoToFolderDoesNotChangeOtherMembershipAndDoesNotDuplicate() {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        let firstID = store.folders[0].id
        let secondID = store.folders[1].id
        let entry = video("sZSlTDlo0Ag")

        XCTAssertTrue(store.add(entry, to: firstID))
        XCTAssertTrue(store.add(entry, to: secondID))
        XCTAssertTrue(store.add(entry, to: secondID))
        XCTAssertEqual(store.folder(firstID)?.videos.map(\.id), [entry.id])
        XCTAssertEqual(store.folder(secondID)?.videos.map(\.id), [entry.id])
        XCTAssertEqual(FavoritesStore(fileURL: file).folders, store.folders)
    }

    @MainActor
    func testAddingInvalidVideoOrUsingMissingFolderIsRejected() {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        let original = store.folders

        XCTAssertFalse(store.add(video("../invalid"), to: original[0].id))
        XCTAssertFalse(store.add(video("sZSlTDlo0Ag"), to: UUID()))
        XCTAssertFalse(store.add(FavoriteVideo(id: "sZSlTDlo0Ag", title: " ", author: "Channel",
                                               savedAt: Date()), to: original[0].id))
        XCTAssertEqual(store.folders, original)
    }

    @MainActor
    func testLegacyFavoritesUpgradeWithoutLosingVideos() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = try JSONEncoder().encode([video("sZSlTDlo0Ag")])
        try original.write(to: file)
        let store = FavoritesStore(fileURL: file)
        XCTAssertTrue(store.isLoaded)
        XCTAssertEqual(store.folders.map(\.name), ["Watch Later", "Favorite"])
        XCTAssertTrue(store.folders[0].videos.isEmpty)
        XCTAssertEqual(store.folders[1].videos.map(\.id), ["sZSlTDlo0Ag"])
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("single-folder-backup")), original)
        XCTAssertEqual(FavoritesStore(fileURL: file).folders, store.folders)
    }

    @MainActor
    func testExistingMultiFolderDocumentWithoutPlaylistSourceStillLoads() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let folderID = UUID()
        let document = """
        {"folders":[{"id":"\(folderID.uuidString)","name":"原有收藏夹","videos":[]}]}
        """
        try Data(document.utf8).write(to: file)
        let store = FavoritesStore(fileURL: file)
        XCTAssertTrue(store.isLoaded)
        XCTAssertEqual(store.folder(folderID)?.name, "原有收藏夹")
        XCTAssertNil(store.folder(folderID)?.sourcePlaylistID)
        XCTAssertNil(store.folder(folderID)?.iconName)
        XCTAssertNil(store.folder(folderID)?.colorHex)
    }

    @MainActor
    func testWriteFailureDoesNotChangeVisibleFoldersOrMembership() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        let original = store.folders
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        XCTAssertNil(store.createFolder(named: "Cannot save"))
        XCTAssertFalse(store.setMembership(for: video("sZSlTDlo0Ag"), folderIDs: [original[0].id]))
        XCTAssertFalse(store.moveFolder(original[0].id, relativeTo: original[1].id, placeAfter: true))
        XCTAssertFalse(store.add(video("sZSlTDlo0Ag"), to: original[0].id))
        XCTAssertEqual(store.folders, original)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testCorruptFileIsPreservedAndCannotBeOverwritten() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("incomplete JSON".utf8)
        try original.write(to: file)
        let store = FavoritesStore(fileURL: file)
        XCTAssertFalse(store.isLoaded)
        XCTAssertNil(store.createFolder(named: "Must not overwrite"))
        XCTAssertEqual(try Data(contentsOf: file), original)
        try Data(#"{"folders":[]}"#.utf8).write(to: file)
        store.reload()
        XCTAssertTrue(store.isLoaded)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testInvalidIDsAndMissingFolderAreRejected() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        XCTAssertFalse(store.setMembership(for: video("../invalid"), folderIDs: [store.folders[0].id]))
        XCTAssertFalse(store.setMembership(for: video("sZSlTDlo0Ag"), folderIDs: [UUID()]))
        XCTAssertTrue(store.folders.allSatisfy { $0.videos.isEmpty })
        try JSONEncoder().encode([video("invalid")]).write(to: file)
        store.reload()
        XCTAssertFalse(store.isLoaded)
    }

    @MainActor
    func testFavoritesAreNotLimitedByWatchHistoryCapacity() {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        let folderID = store.folders[0].id
        for index in 0..<35 {
            store.setMembership(for: video(String(format: "%011d", index)), folderIDs: [folderID])
        }
        XCTAssertEqual(FavoritesStore(fileURL: file).folder(folderID)?.videos.count, 35)
    }

    @MainActor
    func testPlaylistImportCreatesThenMergesOneLocalFolder() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        let first = video("sZSlTDlo0Ag")
        let second = video("dQw4w9WgXcQ")
        let folderID = try XCTUnwrap(store.savePlaylist(
            sourceID: "playlist:PLabc", named: "学习列表", videos: [first]))
        XCTAssertEqual(store.folder(folderID)?.name, "学习列表")
        XCTAssertEqual(store.folder(folderID)?.videos.map(\.id), [first.id])

        XCTAssertTrue(store.renameFolder(folderID, to: "我的课程"))
        XCTAssertEqual(store.savePlaylist(
            sourceID: "playlist:PLabc", named: "上游的新标题", videos: [second, first]), folderID)
        XCTAssertEqual(store.folder(folderID)?.name, "我的课程")
        XCTAssertEqual(store.folder(folderID)?.videos.map(\.id), [second.id, first.id])
        XCTAssertEqual(store.folders.filter { $0.sourcePlaylistID == "playlist:PLabc" }.count, 1)
        XCTAssertEqual(FavoritesStore(fileURL: file).folder(folderID), store.folder(folderID))
    }

    @MainActor
    func testPlaylistImportKeepsExistingSameNamedFolderSeparate() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = FavoritesStore(fileURL: file)
        _ = try XCTUnwrap(store.createFolder(named: "音乐"))
        let imported = try XCTUnwrap(store.savePlaylist(
            sourceID: "mix:RDabc", named: "音乐", videos: [video("sZSlTDlo0Ag")]))
        XCTAssertEqual(store.folder(imported)?.name, "音乐 (2)")
        XCTAssertEqual(store.folder(imported)?.sourcePlaylistID, "mix:RDabc")
    }

    private func video(_ id: String) -> FavoriteVideo {
        FavoriteVideo(id: id, title: "本地收藏", author: "Channel", savedAt: Date())
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("YootubeFavoritesTests-\(UUID().uuidString)")
            .appendingPathComponent("favorites.json")
    }
}
