import XCTest
import WebKit
@testable import Yootube

final class NativeContentTests: XCTestCase {
    private let base = LocalServiceManager.invidiousURL

    func testSearchChannelAndPlaylistRoutesUseNativeContent() throws {
        let searchURL = try XCTUnwrap(URL(string: "\(base.absoluteString)/search?q=swift%20ui&page=2"))
        guard case .search(let search) = NativePageRoute(searchURL) else {
            return XCTFail("Search should use native content")
        }
        XCTAssertEqual(search.query, "swift ui")
        XCTAssertEqual(search.page, 2)

        let channelURL = base.appendingPathComponent("channel/UCwrVwiJllwhJUKXKmjLcckQ")
        guard case .channel(let channel) = NativePageRoute(channelURL) else {
            return XCTFail("Channel should use native content")
        }
        XCTAssertEqual(channel.channelID, "UCwrVwiJllwhJUKXKmjLcckQ")

        let handleURL = base.appendingPathComponent("@AppleDeveloper")
        guard case .channel(let handle) = NativePageRoute(handleURL) else {
            return XCTFail("Channel handle should use native content")
        }
        XCTAssertNil(handle.channelID)
        XCTAssertEqual(handle.youtubeURL?.absoluteString, "https://www.youtube.com/@AppleDeveloper")

        let playlistURL = try XCTUnwrap(URL(string: "\(base.absoluteString)/playlist?list=PLabc"))
        guard case .playlist(let playlist) = NativePageRoute(playlistURL) else {
            return XCTFail("Playlist should use native content")
        }
        XCTAssertEqual(playlist.id, "PLabc")

        let firstMix = try XCTUnwrap(URL(string: "\(base.absoluteString)/mix?list=RDabc&continuation=firstVideo"))
        let secondMix = try XCTUnwrap(URL(string: "\(base.absoluteString)/mix?list=RDabc&continuation=secondVideo"))
        XCTAssertNotEqual(NativePageRoute(firstMix)?.id, NativePageRoute(secondMix)?.id)
    }

    func testPlayerAndUnrelatedServicePagesStayOutsideNativeContent() throws {
        for path in ["/watch?v=sZSlTDlo0Ag", "/embed/sZSlTDlo0Ag", "/preferences", "/login"] {
            let url = try XCTUnwrap(URL(string: base.absoluteString + path))
            XCTAssertNil(NativePageRoute(url), "Unexpected native route for \(path)")
        }
        XCTAssertNil(NativePageRoute(try XCTUnwrap(URL(string: "https://example.com/search?q=swift"))))
    }

    func testToolbarKeepsSearchQueriesAndSubmittedYouTubeLinks() throws {
        let search = try XCTUnwrap(URL(string: "\(base.absoluteString)/search?q=swift%20ui"))
        let channel = base.appendingPathComponent("channel/UCwrVwiJllwhJUKXKmjLcckQ")
        let video = try XCTUnwrap(URL(string: "\(base.absoluteString)/watch?v=sZSlTDlo0Ag"))
        let submittedLink = "https://www.youtube.com/watch?v=sZSlTDlo0Ag"
        XCTAssertEqual(toolbarQuery(for: .page(search)), "swift ui")
        XCTAssertEqual(toolbarQuery(for: .page(video), submittedYouTubeLink: submittedLink), submittedLink)
        XCTAssertEqual(toolbarQuery(for: .page(channel)), "")
        XCTAssertEqual(toolbarQuery(for: .home), "")
    }

    @MainActor
    func testBrowserSelectsNativeContentWithoutChangingWindowOrPlayerRoutes() throws {
        let browser = BrowserModel()
        let searchURL = try XCTUnwrap(URL(string: "\(base.absoluteString)/search?q=swift"))
        browser.loadPage(searchURL)
        guard case .search = browser.nativeRoute else {
            return XCTFail("Browser did not expose the native search page")
        }
        XCTAssertNil(browser.videoDetail)

        let watchURL = try XCTUnwrap(VideoRoute.watchURL(id: "sZSlTDlo0Ag"))
        browser.loadPage(watchURL)
        XCTAssertNil(browser.nativeRoute)
        XCTAssertNotNil(browser.videoDetail)
    }

    func testNativeSearchModelsDecodeAllSupportedCardTypes() throws {
        let data = Data(#"""
        [
          {"type":"video","videoId":"sZSlTDlo0Ag","title":"Video","author":"Creator","authorId":"UC1","lengthSeconds":90},
          {"type":"channel","author":"Creator","authorId":"UC1","subCount":12,"authorThumbnails":[]},
          {"type":"playlist","playlistId":"PL1","title":"List","author":"Creator","videoCount":3,"videos":[]}
        ]
        """#.utf8)
        let results = try JSONDecoder().decode([NativeSearchResult].self, from: data)
        XCTAssertEqual(results.compactMap(\.kind), [.video, .channel, .playlist])
        XCTAssertEqual(Set(results.map(\.id)).count, 3)
    }

    @MainActor
    func testWebViewNavigationIntoSearchIsHandedToNativeContent() async throws {
        let browser = BrowserModel()
        browser.webView.loadHTMLString(
            "<html><body><a id='search' href='\(base.absoluteString)/search?q=inside'>Search</a></body></html>",
            baseURL: nil
        )
        for _ in 0..<100 {
            if !browser.webView.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = try? await browser.webView.evaluateJavaScript("document.getElementById('search').click()")
        for _ in 0..<100 {
            if case .search = browser.nativeRoute { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard case .search(let route) = browser.nativeRoute else {
            return XCTFail("WebView navigation bypassed native search")
        }
        XCTAssertEqual(route.query, "inside")
    }

    func testPlaylistRowsCanRepresentTheSameVideoAtDifferentSourcePositions() {
        let first = PlaylistVideoItem(videoID: "sZSlTDlo0Ag", title: "Same", author: "Creator",
                                      index: 2, lengthSeconds: 10, position: 2)
        let second = PlaylistVideoItem(videoID: "sZSlTDlo0Ag", title: "Same", author: "Creator",
                                       index: 9, lengthSeconds: 10, position: 9)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.videoID, second.videoID)
    }

}
