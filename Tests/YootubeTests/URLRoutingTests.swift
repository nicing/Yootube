import XCTest
@testable import Yootube

final class URLRoutingTests: XCTestCase {
    private let instanceURL = URL(string: "https://inv.example.com")!

    func testSearchTextBecomesEncodedInstanceSearchURL() throws {
        let url = try XCTUnwrap(
            URLRouting.destination(for: "SwiftUI tutorial", instanceURL: instanceURL)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/search")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: "SwiftUI tutorial")])
    }

    func testUnrelatedHostIsSearchedLocally() throws {
        let url = try XCTUnwrap(
            URLRouting.destination(for: "invidious.example.com/watch?v=abc", instanceURL: instanceURL)
        )

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, instanceURL.host)
        XCTAssertEqual(url.path, "/search")
    }

    func testVideoVariantsAreConvertedToLocalWatch() throws {
        for input in [
            "https://www.youtube.com/watch?v=sZSlTDlo0Ag&si=tracking",
            "https://youtu.be/sZSlTDlo0Ag",
            "youtube.com/shorts/sZSlTDlo0Ag",
            "https://m.youtube.com/live/sZSlTDlo0Ag",
            "https://www.youtube-nocookie.com/embed/sZSlTDlo0Ag"
        ] {
            let url = try XCTUnwrap(URLRouting.youtubeDestination(for: input, instanceURL: instanceURL))
            XCTAssertEqual(url.absoluteString, "https://inv.example.com/watch?v=sZSlTDlo0Ag")
        }
    }

    func testTimestampAndPlaylistSurviveConversion() throws {
        let url = try XCTUnwrap(URLRouting.youtubeDestination(
            for: "https://youtu.be/sZSlTDlo0Ag?t=90&list=PLabc&si=tracking", instanceURL: instanceURL))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(query.contains(URLQueryItem(name: "t", value: "90")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "list", value: "PLabc")))
        XCTAssertFalse(query.contains(where: { $0.name == "si" }))
    }

    func testPastedPlaylistOpensLocalPlaylistAndPreservesIndex() throws {
        let input = "https://www.youtube.com/playlist?list=PLabc&index=3&si=tracking"
        XCTAssertTrue(URLRouting.isBulkInsertion(from: "", to: input))
        let url = try XCTUnwrap(URLRouting.youtubeDestination(for: input, instanceURL: instanceURL))
        XCTAssertEqual(url.absoluteString, "https://inv.example.com/playlist?list=PLabc&index=3")
    }

    func testPastedVideoWithMixOpensMixInsteadOfSingleVideo() throws {
        let input = "https://www.youtube.com/watch?v=Qey0V-UtK6U&list=RDQey0V-UtK6U&start_radio=1"
        let url = try XCTUnwrap(URLRouting.destination(for: input, instanceURL: instanceURL))
        XCTAssertEqual(url.absoluteString, "https://inv.example.com/mix?list=RDQey0V-UtK6U&continuation=Qey0V-UtK6U")
        // Clicking a video inside the list must still reach its existing player.
        XCTAssertEqual(URLRouting.youtubeDestination(for: input, instanceURL: instanceURL)?.path, "/watch")
    }

    func testPastedVideoWithRegularPlaylistOpensPlaylist() throws {
        let url = try XCTUnwrap(URLRouting.destination(
            for: "https://youtu.be/Qey0V-UtK6U?list=PLabc&index=4&t=20", instanceURL: instanceURL))
        XCTAssertEqual(url.absoluteString, "https://inv.example.com/playlist?list=PLabc&index=4")
        XCTAssertEqual(URLRouting.destination(for: "https://youtu.be/Qey0V-UtK6U", instanceURL: instanceURL)?.path, "/watch")
    }

    func testLocalPlaylistAndMixRoutesCanBeImported() throws {
        let playlist = try XCTUnwrap(PlaylistImportRoute(
            URL(string: "http://127.0.0.1:38473/playlist?list=PLabc")!))
        XCTAssertEqual(playlist.kind, .playlist)
        XCTAssertEqual(playlist.sourceID, "playlist:PLabc")

        let mix = try XCTUnwrap(PlaylistImportRoute(
            URL(string: "http://127.0.0.1:38473/mix?list=RDabc&continuation=Qey0V-UtK6U")!))
        XCTAssertEqual(mix.kind, .mix)
        XCTAssertEqual(mix.continuation, "Qey0V-UtK6U")
        XCTAssertEqual(mix.sourceID, "mix:RDabc")
        XCTAssertNil(PlaylistImportRoute(URL(string: "https://example.com/playlist?list=PLabc")!))
    }

    func testUntrustedOrIncompleteYouTubeLinksDoNotAutoOpen() {
        for input in ["https://youtube.com.evil.com/watch?v=sZSlTDlo0Ag", "https://youtu.be/abc",
                      "javascript://youtube.com/watch?v=sZSlTDlo0Ag", "https://youtube.com/watch?v=",
                      "https://youtube.com/@", "https://youtube.com/channel", "https://youtube.com/playlist"] {
            XCTAssertNil(URLRouting.youtubeDestination(for: input, instanceURL: instanceURL))
        }
    }

    func testSingleCharacterTypingDoesNotAutoSubmit() {
        XCTAssertFalse(URLRouting.isBulkInsertion(from: "https://youtube.com/@", to: "https://youtube.com/@a"))
        XCTAssertTrue(URLRouting.isBulkInsertion(from: "", to: "https://youtu.be/sZSlTDlo0Ag"))
        XCTAssertTrue(URLRouting.isBulkInsertion(from: "a much longer search query to replace", to: "https://youtu.be/sZSlTDlo0Ag"))
    }

    @MainActor
    func testHistoryDeduplicatesAndPersists() throws {
        let name = "YootubeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let history = WatchHistory(defaults: defaults)
        history.record(id: "sZSlTDlo0Ag", title: "First")
        history.record(id: "dQw4w9WgXcQ", title: "Second")
        history.record(id: "sZSlTDlo0Ag", title: "Updated")
        XCTAssertEqual(history.entries.map(\.title), ["Updated", "Second"])
        XCTAssertEqual(WatchHistory(defaults: defaults).entries, history.entries)
    }

}
