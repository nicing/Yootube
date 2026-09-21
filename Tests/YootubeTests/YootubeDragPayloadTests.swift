import XCTest
import UniformTypeIdentifiers
@testable import Yootube

final class YootubeDragPayloadTests: XCTestCase {
    func testPackagedAppDeclaresSeparateFolderAndVideoDragPayloadTypes() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildScript = try String(contentsOf: projectRoot.appendingPathComponent("scripts/build-dmg.sh"),
                                     encoding: .utf8)

        XCTAssertTrue(buildScript.contains("<key>UTExportedTypeDeclarations</key>"))
        XCTAssertTrue(buildScript.contains("<string>com.local.yootube.folder-drag-payload</string>"))
        XCTAssertTrue(buildScript.contains("<string>com.local.yootube.video-drag-payload</string>"))
        XCTAssertTrue(buildScript.contains("<string>public.json</string>"))
    }

    func testFolderAndVideoRegisterDifferentDragTypes() {
        let folderProvider = YootubeDragPayload.folder(UUID()).itemProvider()
        let videoProvider = YootubeDragPayload.video(id: "sZSlTDlo0Ag", title: "Video",
                                                     author: "Channel").itemProvider()

        XCTAssertTrue(folderProvider.hasItemConformingToTypeIdentifier(
            UTType.yootubeFolderDragPayload.identifier))
        XCTAssertFalse(folderProvider.hasItemConformingToTypeIdentifier(
            UTType.yootubeVideoDragPayload.identifier))
        XCTAssertTrue(videoProvider.hasItemConformingToTypeIdentifier(
            UTType.yootubeVideoDragPayload.identifier))
        XCTAssertFalse(videoProvider.hasItemConformingToTypeIdentifier(
            UTType.yootubeFolderDragPayload.identifier))
    }

    func testFolderPayloadAcceptsOnlyFolderFields() {
        let id = UUID()
        XCTAssertEqual(YootubeDragPayload.folder(id).sourceFolderID, id)
        XCTAssertNil(YootubeDragPayload.video(id: "sZSlTDlo0Ag", title: "Video", author: "Channel")
            .sourceFolderID)
    }

    func testVideoPayloadBuildsValidatedFavorite() throws {
        let date = Date(timeIntervalSince1970: 123)
        let payload = YootubeDragPayload.video(id: "sZSlTDlo0Ag", title: "  Video  ", author: " Channel ")
        let video = try XCTUnwrap(payload.favoriteVideo(savedAt: date))
        XCTAssertEqual(video.id, "sZSlTDlo0Ag")
        XCTAssertEqual(video.title, "Video")
        XCTAssertEqual(video.author, "Channel")
        XCTAssertEqual(video.savedAt, date)
    }

    func testVideoPayloadRejectsInvalidOrOversizedExternalData() {
        XCTAssertNil(YootubeDragPayload.video(id: "../invalid", title: "Video", author: "Channel").favoriteVideo())
        XCTAssertNil(YootubeDragPayload.video(id: "sZSlTDlo0Ag", title: " ", author: "Channel").favoriteVideo())
        XCTAssertNil(YootubeDragPayload.video(id: "sZSlTDlo0Ag", title: String(repeating: "x", count: 501),
                                              author: "Channel").favoriteVideo())
        XCTAssertNil(YootubeDragPayload.video(id: "sZSlTDlo0Ag", title: "Video",
                                              author: String(repeating: "x", count: 201)).favoriteVideo())
    }

    func testPayloadRoundTripsThroughCodable() throws {
        let original = YootubeDragPayload.video(id: "sZSlTDlo0Ag", title: "Video", author: "Channel")
        XCTAssertEqual(try JSONDecoder().decode(YootubeDragPayload.self,
                                                from: JSONEncoder().encode(original)), original)
    }
}
