import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let yootubeFolderDragPayload = UTType(exportedAs: "com.local.yootube.folder-drag-payload",
                                                  conformingTo: .json)
    static let yootubeVideoDragPayload = UTType(exportedAs: "com.local.yootube.video-drag-payload",
                                                 conformingTo: .json)
}

struct YootubeDragPayload: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case folder
        case video
    }

    let kind: Kind
    let folderID: UUID?
    let videoID: String?
    let title: String?
    let author: String?

    static let supportedContentTypes: [UTType] = [.yootubeFolderDragPayload, .yootubeVideoDragPayload]

    var contentType: UTType {
        kind == .folder ? .yootubeFolderDragPayload : .yootubeVideoDragPayload
    }

    func itemProvider() -> NSItemProvider {
        guard let data = try? JSONEncoder().encode(self) else { return NSItemProvider() }
        return NSItemProvider(item: data as NSData, typeIdentifier: contentType.identifier)
    }

    static func folder(_ id: UUID) -> Self {
        Self(kind: .folder, folderID: id, videoID: nil, title: nil, author: nil)
    }

    static func video(id: String, title: String, author: String?) -> Self {
        Self(kind: .video, folderID: nil, videoID: id, title: title, author: author)
    }

    var sourceFolderID: UUID? {
        guard kind == .folder, videoID == nil, title == nil, author == nil else { return nil }
        return folderID
    }

    func favoriteVideo(savedAt: Date = Date()) -> FavoriteVideo? {
        guard kind == .video, folderID == nil,
              let videoID, VideoRoute.watchURL(id: videoID) != nil,
              let title else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAuthor = (author ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle.count <= 500, cleanAuthor.count <= 200 else { return nil }
        return FavoriteVideo(id: videoID, title: cleanTitle, author: cleanAuthor, savedAt: savedAt)
    }
}

struct YootubeVideoDragPreview: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(KumoTheme.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 280, alignment: .leading)
            .background(KumoTheme.base,
                        in: RoundedRectangle(cornerRadius: KumoTheme.radiusSmall))
    }
}
