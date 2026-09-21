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
        return script
    }()
}
