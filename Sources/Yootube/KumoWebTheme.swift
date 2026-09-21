import Foundation

// Applies only to local search/channel/preferences documents, never to the player.
enum KumoWebTheme {
    static let script = baseScript + iconScript
    private static let baseScript = #"""
    (() => {
      if (location.origin !== 'http://127.0.0.1:38473' || location.pathname.startsWith('/embed/')) return;
      const style = document.createElement('style');
      style.id = 'yootube-kumo-theme';
      style.textContent = `
        :root { color-scheme:light; --yt-canvas:#ffffff; --yt-base:#fafafc; --yt-recessed:#f5f5f7; --yt-tint:rgba(210,210,215,.64); --yt-text:#1d1d1f; --yt-subtle:#7a7a7a; --yt-line:#e0e0e0; --yt-link:#b42318; }
        @media(prefers-color-scheme:dark) {
          :root { color-scheme:dark; --yt-canvas:#272729; --yt-base:#2a2a2c; --yt-recessed:#252527; --yt-tint:#333333; --yt-text:#ffffff; --yt-subtle:#cccccc; --yt-line:#333333; --yt-link:#ff6b6b; }
        }
        html,body,#contents { background:var(--yt-canvas)!important; color:var(--yt-text)!important; font-family:-apple-system,BlinkMacSystemFont,sans-serif!important; }
        body { font-size:14px; line-height:1.5; }
        #toggle_theme { display:none!important; }
        a { color:var(--yt-link)!important; }
        h1,h2,h3,h4,h5,p { color:inherit!important; }
        h1 { font-size:26px!important; letter-spacing:-.5px; }
        h2 { font-size:20px!important; }
        .pure-form input:not([type=checkbox]):not([type=radio]),.pure-form select,.pure-form textarea {
          background:var(--yt-base)!important; color:var(--yt-text)!important; border:1px solid var(--yt-line)!important;
          border-radius:8px!important; box-shadow:none!important; padding:8px 12px!important; font:inherit!important;
        }
        .pure-form input:focus,.pure-form select:focus,.pure-form textarea:focus { outline:2px solid var(--yt-subtle)!important; outline-offset:2px; }
        .pure-button,button:not(.vjs-control) { background:var(--yt-base)!important; color:var(--yt-text)!important; border:1px solid var(--yt-line)!important; border-radius:8px!important; min-height:36px; padding:6px 12px; font:inherit; }
        .pure-button:hover { background:var(--yt-tint)!important; }
        .pure-button-primary { background:#e70d21!important; color:#fff!important; border-color:#e70d21!important; }
        .thumbnail { border-radius:8px; overflow:hidden; }
        .h-box { border-radius:8px; }
        hr { border-color:var(--yt-line)!important; }
        .footer,.footer a { color:var(--yt-subtle)!important; }
        .pure-menu-selected a,.pure-menu-link:hover { background:var(--yt-tint)!important; }
        a:focus-visible,button:focus-visible { outline:2px solid var(--yt-subtle); outline-offset:2px; }
      `;
      document.head.appendChild(style);
    })();
    """#

    private static let iconScript: String = {
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("Yootube_Yootube.bundle")
        let bundle = packaged.flatMap(Bundle.init(url:)) ?? Bundle.module
        let icons = ["ion-ios-search": "magnifying-glass", "ion-ios-cog": "gear-six",
                     "ion-ios-home": "house", "ion-ios-person": "user",
                     "ion-ios-arrow-back": "arrow-left", "ion-ios-arrow-forward": "arrow-right",
                     "ion-ios-add": "plus", "ion-ios-remove": "minus-circle",
                     "ion-ios-thumbs-up": "thumbs-up", "ion-ios-play": "play",
                     "ion-ios-arrow-down": "caret-down", "ion-ios-arrow-up": "caret-up",
                     "ion-ios-eye": "eye", "ion-ios-lock": "lock", "ion-ios-unlock": "lock-open",
                     "ion-ios-notifications": "bell", "ion-ios-notifications-outline": "bell",
                     "ion-ios-paper": "newspaper", "ion-ios-videocam": "video-camera",
                     "ion-ios-wallet": "wallet", "ion-logo-github": "github-logo",
                     "ion-logo-javascript": "code", "ion-logo-rss": "rss",
                     "ion-md-add": "plus", "ion-md-checkmark-circle": "check-circle",
                     "ion-md-close": "x", "ion-md-create": "pencil-simple",
                     "ion-md-globe": "globe", "ion-md-headset": "headphones",
                     "ion-md-save": "floppy-disk", "ion-md-trash": "trash"]
        let css = icons.sorted(by: { $0.key < $1.key }).compactMap { legacy, name -> String? in
            guard let url = bundle.url(forResource: name, withExtension: "svg", subdirectory: "Icons"),
                  let data = try? Data(contentsOf: url) else { return nil }
            let mask = "url(data:image/svg+xml;base64,\(data.base64EncodedString()))"
            return ".\(legacy):before {content:''!important;display:inline-block;width:16px;height:16px;background:currentColor;mask:\(mask) center/contain no-repeat;-webkit-mask:\(mask) center/contain no-repeat;}"
        }.joined(separator: "\n")
        let json = String(data: try! JSONEncoder().encode(css), encoding: .utf8)!
        return "\n(() => { const style = document.getElementById('yootube-kumo-theme'); if (style) style.textContent += \(json); })();"
    }()
}
