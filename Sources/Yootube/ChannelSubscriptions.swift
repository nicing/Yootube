import Foundation

struct ChannelSubscription: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let avatarSource: String?
    let subscribedAt: Date

    var url: URL {
        LocalServiceManager.invidiousURL.appendingPathComponent("channel").appendingPathComponent(id)
    }

    var avatarURL: URL? { VideoAPI.imageURL(avatarSource) }
}

@MainActor
final class ChannelSubscriptionStore: ObservableObject {
    static let defaultFileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Yootube/subscriptions.json")

    @Published private(set) var channels: [ChannelSubscription] = []
    @Published private(set) var isLoaded = false
    @Published var errorMessage: String?
    let fileURL: URL

    init(fileURL: URL = ChannelSubscriptionStore.defaultFileURL) {
        self.fileURL = fileURL
        reload()
    }

    func contains(_ channelID: String) -> Bool {
        channels.contains { $0.id == channelID }
    }

    @discardableResult
    func toggle(_ channel: NativeChannel) -> Bool {
        guard isLoaded else { return false }
        if contains(channel.authorId) {
            return save(channels.filter { $0.id != channel.authorId })
        }
        let subscription = ChannelSubscription(
            id: channel.authorId,
            name: channel.author,
            avatarSource: channel.authorThumbnails?.last?.url,
            subscribedAt: Date()
        )
        guard Self.isValid(subscription) else { return false }
        return save([subscription] + channels)
    }

    func reload() {
        do {
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(ChannelSubscriptionsDocument.self, from: data)
            try Self.validate(document.channels)
            channels = document.channels
            isLoaded = true
            errorMessage = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            isLoaded = save([])
        } catch {
            isLoaded = false
            errorMessage = L10n.t("无法读取本地订阅，原文件已保留。请检查文件后重新读取。\n\(fileURL.path)")
        }
    }

    @discardableResult
    func replaceAll(with imported: [ChannelSubscription]) -> Bool {
        guard isLoaded else { return false }
        do {
            try Self.validate(imported)
            return save(imported)
        } catch {
            errorMessage = L10n.t("备份中的频道订阅无效，未修改本地数据。")
            return false
        }
    }

    nonisolated static func validate(_ channels: [ChannelSubscription]) throws {
        guard channels.allSatisfy(Self.isValid),
              Set(channels.map(\.id)).count == channels.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    nonisolated private static func isValid(_ channel: ChannelSubscription) -> Bool {
        let validID = !channel.id.isEmpty && channel.id.count <= 128 && channel.id.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
        }
        let name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let validName = !name.isEmpty && name.count <= 200
        return validID && validName
    }

    @discardableResult
    private func save(_ updated: [ChannelSubscription]) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(ChannelSubscriptionsDocument(channels: updated))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            channels = updated
            isLoaded = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = L10n.t("订阅保存失败，此次更改未生效。请检查磁盘空间和文件权限后重试。")
            return false
        }
    }
}

private struct ChannelSubscriptionsDocument: Codable {
    let channels: [ChannelSubscription]
}
