import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    @ObservedObject var model: BrowserModel
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> WKWebView {
        model.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WebKit's media query follows this appearance without reloading the page.
        nsView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}
