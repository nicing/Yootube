import Foundation

enum URLRouting {
    static func isBulkInsertion(from previous: String, to current: String) -> Bool {
        let old = Array(previous)
        let new = Array(current)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        return new.count - prefix - suffix > 1
    }

    static func youtubeDestination(for input: String, instanceURL: URL) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: { $0.isWhitespace }),
              let source = URLComponents(string: value.contains("://") ? value : "https://\(value)"),
              ["http", "https"].contains(source.scheme?.lowercased() ?? ""),
              let host = source.host?.lowercased(),
              ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be", "youtube-nocookie.com", "www.youtube-nocookie.com"].contains(host),
              var target = URLComponents(url: instanceURL, resolvingAgainstBaseURL: false) else { return nil }
        let parts = source.path.split(separator: "/").map(String.init)
        var query = source.queryItems ?? []
        var videoID: String?
        if host.hasSuffix("youtu.be") { videoID = parts.first }
        else if ["shorts", "embed", "live"].contains(parts.first ?? "") { videoID = parts.dropFirst().first }
        else if source.path == "/watch" { videoID = query.first(where: { $0.name == "v" })?.value }
        if let videoID {
            guard videoID.count == 11,
                  videoID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { return nil }
            target.path = "/watch"
            query = query.filter { ["t", "start", "list", "index"].contains($0.name) }
            query.insert(URLQueryItem(name: "v", value: videoID), at: 0)
            if !query.contains(where: { $0.name == "t" }), let fragment = source.fragment, fragment.hasPrefix("t=") {
                query.append(URLQueryItem(name: "t", value: String(fragment.dropFirst(2))))
            }
        } else {
            let playlist = source.path == "/playlist" && query.contains(where: { $0.name == "list" && !($0.value ?? "").isEmpty })
            let channel = ["channel", "user", "c"].contains(parts.first ?? "") && parts.count >= 2
            let handle = parts.first.map { $0.hasPrefix("@") && $0.count > 1 } ?? false
            guard playlist || channel || handle else { return nil }
            target.path = source.path
            query = query.filter { ["list", "index"].contains($0.name) }
        }
        target.queryItems = query.isEmpty ? nil : query
        target.fragment = nil
        return target.url
    }

    static func destination(for input: String, instanceURL: URL) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let youtube = youtubeDestination(for: value, instanceURL: instanceURL) {
            // Home input opens the collection; links clicked within it still use
            // youtubeDestination directly to reach the native video player.
            if var parts = URLComponents(url: youtube, resolvingAgainstBaseURL: false),
               ["/watch", "/playlist"].contains(parts.path),
               let list = parts.queryItems?.first(where: { $0.name == "list" })?.value,
               !list.isEmpty {
                let query = parts.queryItems ?? []
                if list.hasPrefix("RD") {
                    parts.path = "/mix"
                    parts.queryItems = [URLQueryItem(name: "list", value: list)]
                    if let seed = query.first(where: { $0.name == "v" })?.value {
                        parts.queryItems?.append(URLQueryItem(name: "continuation", value: seed))
                    }
                } else {
                    parts.path = "/playlist"
                    parts.queryItems = query.filter { ["list", "index"].contains($0.name) }
                }
                return parts.url
            }
            return youtube
        }
        if let local = URL(string: value), local.scheme == instanceURL.scheme,
           local.host == instanceURL.host, local.port == instanceURL.port { return local }

        guard var components = URLComponents(
            url: instanceURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: value)]
        return components.url
    }

}
