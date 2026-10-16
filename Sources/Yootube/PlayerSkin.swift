import Foundation

enum PlayerSkin {
    static var script: String {
        "window.yootubeLanguage = '\(AppLanguage.current.playerLanguageCode)';\n" + baseScript
    }

    private static let baseScript: String = {
        // SwiftPM's generated accessor searches beside the executable, while a macOS
        // application ships resources in Contents/Resources.
        let appBundle = Bundle.main.resourceURL?
            .appendingPathComponent("Yootube_Yootube.bundle")
        let bundle = appBundle.flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let url = bundle.url(forResource: "PlayerSkin", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("Missing bundled player controls")
        }
        let icons = [
            "VOLUME_ON": "player-volume-on",
            "VOLUME_OFF": "player-volume-off",
            "CAPTIONS_OFF": "player-captions-off",
            "CAPTIONS_ON": "player-captions-on",
            "THEATER_OFF": "player-theater-off",
            "THEATER_ON": "player-theater-on",
            "SETTINGS": "player-settings"
        ]
        return icons.reduce(script) { result, icon in
            guard let url = bundle.url(forResource: icon.value, withExtension: "svg", subdirectory: "Icons"),
                  let svg = try? String(contentsOf: url, encoding: .utf8),
                  let encoded = try? JSONEncoder().encode(svg),
                  let literal = String(data: encoded, encoding: .utf8) else {
                preconditionFailure("Missing bundled player icon: \(icon.value)")
            }
            return result.replacingOccurrences(of: "'__FIGMA_\(icon.key)__'", with: literal)
        }
    }()
}
