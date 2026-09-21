import AVFoundation
import XCTest
@testable import Yootube

final class VideoDetailTests: XCTestCase {
    private enum RetryFailure: Error { case unavailable }

    func testPictureInPictureIgnoresTheBriefSystemPauseWhileClosing() {
        var intent = PictureInPicturePlaybackIntent(shouldPlay: true)
        intent.observe(.paused)
        XCTAssertTrue(intent.shouldPlay)
        intent.observe(.paused)
        XCTAssertTrue(intent.shouldPlay)
        intent.observe(.paused)
        XCTAssertFalse(intent.shouldPlay)
        intent.observe(.waitingToPlayAtSpecifiedRate)
        XCTAssertTrue(intent.shouldPlay)
    }

    @MainActor
    func testVideoRequestRetriesTransientFailuresUntilItSucceeds() async throws {
        var attempts = 0
        var sleeps = 0
        let value = try await VideoRequestRetry.run(
            maxAttempts: 4,
            delay: .seconds(1),
            sleep: { _ in sleeps += 1 }
        ) {
            attempts += 1
            if attempts < 3 { throw RetryFailure.unavailable }
            return "ready"
        }

        XCTAssertEqual(value, "ready")
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(sleeps, 2)
    }

    @MainActor
    func testVideoRequestStopsAfterTheAttemptLimit() async {
        var attempts = 0

        do {
            let _: String = try await VideoRequestRetry.run(
                maxAttempts: 3,
                delay: .zero,
                sleep: { _ in }
            ) {
                attempts += 1
                throw RetryFailure.unavailable
            }
            XCTFail("Expected the retry limit to throw")
        } catch {
            XCTAssertEqual(attempts, 3)
        }
    }

    @MainActor
    func testVideoRequestCancellationStopsBeforeAnotherAttempt() async {
        var attempts = 0

        do {
            let _: String = try await VideoRequestRetry.run(
                maxAttempts: 3,
                delay: .seconds(1),
                sleep: { _ in throw CancellationError() }
            ) {
                attempts += 1
                throw RetryFailure.unavailable
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(attempts, 1)
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testEmbedPreservesTimestampAndPlaylistButForcesLocalPlayback() throws {
        let route = try XCTUnwrap(VideoRoute(URL(string: "http://127.0.0.1:38473/watch?v=sZSlTDlo0Ag&start=90&list=PLabc&index=2&local=false&autoplay=1")!))
        XCTAssertEqual(route.id, "sZSlTDlo0Ag")
        XCTAssertEqual(route.embedURL.path, "/embed/sZSlTDlo0Ag")
        let items = try XCTUnwrap(URLComponents(url: route.embedURL, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(items.contains(URLQueryItem(name: "t", value: "90")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "list", value: "PLabc")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "index", value: "2")))
        XCTAssertEqual(items.filter { $0.name == "local" }, [URLQueryItem(name: "local", value: "true")])
        XCTAssertEqual(items.filter { $0.name == "autoplay" }, [URLQueryItem(name: "autoplay", value: "1")])
    }

    func testRoutesRejectOtherOriginsAndMalformedPaths() {
        for input in [
            "https://youtube.com/watch?v=sZSlTDlo0Ag",
            "http://127.0.0.1:38475/watch?v=sZSlTDlo0Ag",
            "https://127.0.0.1:38473/watch?v=sZSlTDlo0Ag",
            "http://127.0.0.1:38473/embed/sZSlTDlo0Ag/extra",
            "http://127.0.0.1:38473/watch?v=short",
            "http://127.0.0.1:38473/watch?v=sZSlTDlo0A%2F"
        ] { XCTAssertNil(VideoRoute(URL(string: input)!), input) }
    }

    func testPlaylistEmbedNavigationCanBecomeNewDetailRoute() throws {
        let route = try XCTUnwrap(VideoRoute(URL(string: "http://127.0.0.1:38473/embed/4Ui09XbYf1A?list=PLabc&index=3")!))
        XCTAssertEqual(route.id, "4Ui09XbYf1A")
        XCTAssertEqual(route.embedURL.host, "127.0.0.1")
    }

    func testUntrustedRecommendationIDCannotBuildURL() {
        for id in ["", "../../watch", "1234567890&", "１２３４５６７８９０１", "sZSlTDlo0Ag/other"] {
            XCTAssertNil(VideoRoute.watchURL(id: id))
            XCTAssertNil(VideoRoute.youtubeURL(id: id))
        }
        XCTAssertEqual(VideoRoute.watchURL(id: "sZSlTDlo0Ag")?.absoluteString, "http://127.0.0.1:38473/watch?v=sZSlTDlo0Ag")
        XCTAssertEqual(VideoRoute.youtubeURL(id: "sZSlTDlo0Ag")?.absoluteString,
                       "https://www.youtube.com/watch?v=sZSlTDlo0Ag")
    }

    func testAutoplayChoosesFirstValidRecommendationAfterCurrentVideo() throws {
        let data = Data(#"[{"videoId":"sZSlTDlo0Ag","title":"Current"},{"videoId":"bad","title":"Invalid"},{"videoId":"4Ui09XbYf1A","title":"Next"}]"#.utf8)
        let videos = try JSONDecoder().decode([RecommendedVideo].self, from: data)
        XCTAssertEqual(
            nextAutoplayURL(currentVideoID: "sZSlTDlo0Ag", recommendedVideos: videos)?.absoluteString,
            "http://127.0.0.1:38473/watch?v=4Ui09XbYf1A"
        )
    }

    @MainActor
    func testAutoplayDefaultsOnAndPersistsTheUsersChoice() throws {
        let defaultsName = "YootubeAutoplayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let route = try XCTUnwrap(VideoRoute(URL(string: "http://127.0.0.1:38473/watch?v=sZSlTDlo0Ag")!))
        let history = WatchHistory(defaults: defaults)

        let first = VideoDetailModel(route: route, history: history, defaults: defaults) { _ in }
        XCTAssertTrue(first.autoplayEnabled)
        first.autoplayEnabled = false
        first.stop()

        let restored = VideoDetailModel(route: route, history: history, defaults: defaults) { _ in }
        XCTAssertFalse(restored.autoplayEnabled)
        restored.stop()
    }

    @MainActor
    func testPlayerUsesValidatedRealVideoAspectRatio() throws {
        let route = try XCTUnwrap(VideoRoute(URL(string: "http://127.0.0.1:38473/watch?v=sZSlTDlo0Ag")!))
        let model = VideoDetailModel(route: route, history: WatchHistory()) { _ in }
        XCTAssertEqual(model.playerAspectRatio, 16.0 / 9.0)
        model.setPlayerAspectRatio(2)
        XCTAssertEqual(model.playerAspectRatio, 2)
        model.setPlayerAspectRatio(.infinity)
        XCTAssertEqual(model.playerAspectRatio, 2)
        model.stop()
    }

    func testFKeyCyclesThroughTheaterFullScreenAndDefault() {
        XCTAssertEqual(PlayerDisplayCycleAction.resolve(theaterMode: false, playerFullScreen: false),
                       .enterTheater)
        XCTAssertEqual(PlayerDisplayCycleAction.resolve(theaterMode: true, playerFullScreen: false),
                       .enterPlayerFullScreen)
        XCTAssertEqual(PlayerDisplayCycleAction.resolve(theaterMode: true, playerFullScreen: true),
                       .exitPlayerFullScreenAndTheater)
        XCTAssertEqual(PlayerDisplayCycleAction.resolve(theaterMode: false, playerFullScreen: true),
                       .exitPlayerFullScreenAndTheater)
    }

    @MainActor
    func testFirstFUpdatesTheaterStateBeforeThePlayerReplies() throws {
        let route = try XCTUnwrap(VideoRoute(URL(string: "http://127.0.0.1:38473/watch?v=sZSlTDlo0Ag")!))
        let model = VideoDetailModel(route: route, history: WatchHistory()) { _ in }

        model.cycleDisplayMode()

        XCTAssertTrue(model.playerTheaterMode)
        model.stop()
    }

    @MainActor
    func testOpeningSidebarCanExitTheaterModeImmediately() throws {
        let route = try XCTUnwrap(VideoRoute(URL(string: "http://127.0.0.1:38473/watch?v=sZSlTDlo0Ag")!))
        let model = VideoDetailModel(route: route, history: WatchHistory()) { _ in }
        model.setPlayerTheaterMode(true)

        model.exitTheaterMode()

        XCTAssertFalse(model.playerTheaterMode)
        model.stop()
    }

    func testOptionalMetadataAndPlainTextCommentsDecode() throws {
        let video = try JSONDecoder().decode(VideoMetadata.self, from: Data(#"{"videoId":"sZSlTDlo0Ag","title":"A title","author":"Channel","authorId":"UCtest"}"#.utf8))
        XCTAssertEqual(video.title, "A title")
        XCTAssertNil(video.recommendedVideos)
        let page = try JSONDecoder().decode(VideoComments.self, from: Data(#"{"comments":[{"commentId":"1","author":"Viewer","content":"<script>text only</script>"}],"continuation":"next"}"#.utf8))
        XCTAssertEqual(page.comments.first?.content, "<script>text only</script>")
        XCTAssertEqual(page.continuation, "next")
    }

    func testBuildsCacheOptionsFromMuxedMP4Streams() throws {
        let data = Data(#"{"videoId":"sZSlTDlo0Ag","title":"A title","author":"Channel","authorId":"UCtest","formatStreams":[{"url":"http://127.0.0.1:38473/videoplayback?itag=18","type":"video/mp4; codecs=\"avc1, mp4a\"","qualityLabel":"360p","bitrate":500},{"url":"http://127.0.0.1:38473/videoplayback?itag=22","container":"mp4","qualityLabel":"720p","bitrate":1000},{"url":"http://127.0.0.1:38473/videoplayback?itag=43","container":"webm","qualityLabel":"1080p","bitrate":2000}]}"#.utf8)
        let video = try JSONDecoder().decode(VideoMetadata.self, from: data)
        XCTAssertEqual(video.cacheOptions.map(\.height), [720, 360])
        XCTAssertTrue(video.cacheOptions.allSatisfy { !$0.requiresMuxing })
    }

    func testCacheOptionsKeepHighestBitrateForEachResolution() throws {
        let data = Data(#"{"videoId":"sZSlTDlo0Ag","title":"A title","author":"Channel","authorId":"UCtest","formatStreams":[{"url":"http://127.0.0.1:38473/videoplayback?itag=1","container":"mp4","qualityLabel":"360p","bitrate":900},{"url":"http://127.0.0.1:38473/videoplayback?itag=2","container":"mp4","qualityLabel":"720p","bitrate":800},{"url":"http://127.0.0.1:38473/videoplayback?itag=3","container":"mp4","qualityLabel":"720p","bitrate":1200}]}"#.utf8)
        let video = try JSONDecoder().decode(VideoMetadata.self, from: data)
        XCTAssertEqual(video.cacheOptions.map(\.height), [720, 360])
        XCTAssertTrue(video.cacheOptions.first?.videoURL.absoluteString.contains("itag=3") == true)
    }

    func testCacheOptionsRejectUnsupportedOrUntrustedStreams() throws {
        let data = Data(#"{"videoId":"sZSlTDlo0Ag","title":"A title","author":"Channel","authorId":"UCtest","formatStreams":[{"url":"http://127.0.0.1:38473/videoplayback?itag=18","container":"mp4","qualityLabel":"360p","bitrate":500},{"url":"http://127.0.0.1:38473/videoplayback?itag=43","container":"webm","qualityLabel":"1080p","bitrate":2000},{"url":"https://googlevideo.com/videoplayback?itag=22","container":"mp4","qualityLabel":"720p","bitrate":1000},{"url":"http://127.0.0.1:38473/api/v1/videos/id","container":"mp4","qualityLabel":"480p","bitrate":700}]}"#.utf8)
        let video = try JSONDecoder().decode(VideoMetadata.self, from: data)
        XCTAssertEqual(video.cacheOptions.map(\.height), [360])
    }

    func testCacheOptionsInclude1080pH264WithBestAACAudio() throws {
        let data = Data(#"{"videoId":"sZSlTDlo0Ag","title":"A title","author":"Channel","authorId":"UCtest","formatStreams":[{"url":"http://127.0.0.1:38473/videoplayback?itag=18","container":"mp4","qualityLabel":"360p","bitrate":500}],"adaptiveFormats":[{"url":"http://127.0.0.1:38473/videoplayback?itag=137","container":"mp4","type":"video/mp4; codecs=\"avc1.640028\"","qualityLabel":"1080p","bitrate":5000,"clen":"103337898"},{"url":"http://127.0.0.1:38473/videoplayback?itag=399","container":"mp4","type":"video/mp4; codecs=\"av01.0.08M.08\"","qualityLabel":"1080p","bitrate":6000},{"url":"http://127.0.0.1:38473/videoplayback?itag=139","container":"m4a","type":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":48000},{"url":"http://127.0.0.1:38473/videoplayback?itag=140","container":"m4a","type":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"clen":3592636}]}"#.utf8)
        let video = try JSONDecoder().decode(VideoMetadata.self, from: data)
        let option = try XCTUnwrap(video.cacheOptions.first)
        XCTAssertEqual(video.cacheOptions.map(\.height), [1080, 360])
        XCTAssertTrue(option.videoURL.absoluteString.contains("itag=137"))
        XCTAssertEqual(option.videoByteCount, 103_337_898)
        XCTAssertTrue(option.audioURL?.absoluteString.contains("itag=140") == true)
        XCTAssertEqual(option.audioByteCount, 3_592_636)
    }

    func testMetadataDecodesWhenInvidiousReturnsBitrateAsString() throws {
        let data = Data(#"{"videoId":"ui8kUKuLBaU","title":"Free","author":"Florence + The Machine","authorId":"UC5MujsH-hrVWHBBfSSmv18A","formatStreams":[{"url":"http://127.0.0.1:38473/videoplayback?itag=18","type":"video/mp4","qualityLabel":"360p","bitrate":"215141"}],"recommendedVideos":[{"videoId":"sZSlTDlo0Ag","title":"Recommended","author":"Channel"}]}"#.utf8)
        let video = try JSONDecoder().decode(VideoMetadata.self, from: data)
        XCTAssertEqual(video.author, "Florence + The Machine")
        XCTAssertEqual(video.formatStreams?.first?.bitrate, 215_141)
        XCTAssertEqual(video.recommendedVideos?.first?.title, "Recommended")
    }

    func testCacheStreamsAcceptOnlyLocalVideoProxyURLs() throws {
        let local = try JSONDecoder().decode(VideoFormat.self, from: Data(#"{"url":"http://127.0.0.1:38473/videoplayback?itag=22","container":"mp4"}"#.utf8))
        let remote = try JSONDecoder().decode(VideoFormat.self, from: Data(#"{"url":"https://googlevideo.com/videoplayback?itag=22","container":"mp4"}"#.utf8))
        let wrongPath = try JSONDecoder().decode(VideoFormat.self, from: Data(#"{"url":"http://127.0.0.1:38473/api/v1/videos/id","container":"mp4"}"#.utf8))
        XCTAssertEqual(VideoStreamProxy.localURL(for: local)?.absoluteString,
                       "http://127.0.0.1:38473/companion/videoplayback?itag=22")
        XCTAssertNil(VideoStreamProxy.localURL(for: remote))
        XCTAssertNil(VideoStreamProxy.localURL(for: wrongPath))
    }

    func testPictureInPictureRebuildsOnlyAllowedGoogleVideoURLs() throws {
        let valid = try JSONDecoder().decode(VideoFormat.self, from: Data(#"{"url":"http://127.0.0.1:38473/videoplayback?itag=18&sig=a%2Fb%3D&host=rr3---sn-test.googlevideo.com","container":"mp4","qualityLabel":"360p"}"#.utf8))
        let upstream = try XCTUnwrap(VideoStreamProxy.upstreamURL(for: valid))
        XCTAssertEqual(upstream.scheme, "https")
        XCTAssertEqual(upstream.host, "rr3---sn-test.googlevideo.com")
        XCTAssertNil(upstream.port)
        XCTAssertNil(upstream.user)
        XCTAssertNil(upstream.password)
        XCTAssertEqual(upstream.path, "/videoplayback")
        XCTAssertEqual(URLComponents(url: upstream, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "itag", value: "18"), URLQueryItem(name: "sig", value: "a/b=")])

        for source in [
            "http://127.0.0.1:38473/videoplayback?host=googlevideo.com.evil.example",
            "http://127.0.0.1:38473/videoplayback?host=evilgooglevideo.com",
            "http://127.0.0.1:38473/videoplayback?host=googlevideo.com%3A443",
            "http://127.0.0.1:38473/videoplayback?host=user%40edge.googlevideo.com",
            "http://127.0.0.1:38473/videoplayback?host=edge%0A.googlevideo.com",
            "http://127.0.0.1:38473/videoplayback?host=edge..googlevideo.com",
            "http://127.0.0.1:38473/videoplayback?host=a.googlevideo.com&host=b.googlevideo.com",
            "http://127.0.0.1:38473/api/v1/videos/id?host=rr3---sn-test.googlevideo.com",
            "https://rr3---sn-test.googlevideo.com/videoplayback?itag=18"
        ] {
            let stream = try JSONDecoder().decode(VideoFormat.self, from: Data(#"{"url":"\#(source)","container":"mp4"}"#.utf8))
            XCTAssertNil(VideoStreamProxy.upstreamURL(for: stream), source)
        }
    }

    func testPictureInPictureChoosesBestMuxedMP4Stream() throws {
        let data = Data(#"{"videoId":"sZSlTDlo0Ag","title":"A title","author":"Channel","authorId":"UCtest","formatStreams":[{"url":"http://127.0.0.1:38473/videoplayback?itag=18&host=a.googlevideo.com","container":"mp4","qualityLabel":"360p","bitrate":500},{"url":"http://127.0.0.1:38473/videoplayback?itag=22&host=b.googlevideo.com","container":"mp4","qualityLabel":"720p","bitrate":1000},{"url":"http://127.0.0.1:38473/videoplayback?itag=43&host=c.googlevideo.com","container":"webm","qualityLabel":"1080p","bitrate":2000}]}"#.utf8)
        let video = try JSONDecoder().decode(VideoMetadata.self, from: data)
        XCTAssertEqual(URLComponents(url: video.pictureInPictureURL!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "itag" })?.value, "22")
    }

    func testCaptionCacheAcceptsOnlyThisVideosLocalCaptionEndpoint() {
        XCTAssertNotNil(VideoAPI.captionURL(
            "/api/v1/captions/sZSlTDlo0Ag?label=Chinese+%28Simplified%29",
            videoID: "sZSlTDlo0Ag"
        ))
        XCTAssertNil(VideoAPI.captionURL(
            "/api/v1/captions/anotherVideo?label=English",
            videoID: "sZSlTDlo0Ag"
        ))
        XCTAssertNil(VideoAPI.captionURL("https://example.com/captions.vtt", videoID: "sZSlTDlo0Ag"))
    }

    func testAvatarsUseOnlyLocalAllowedProxyPaths() {
        XCTAssertEqual(VideoAPI.avatarURL("https://yt3.ggpht.com/avatar=s88")?.absoluteString, "http://127.0.0.1:38473/ggpht/avatar=s88")
        XCTAssertNil(VideoAPI.avatarURL("https://yt3.ggpht.com.evil.test/avatar"))
        XCTAssertNil(VideoAPI.avatarURL("file:///etc/passwd"))
        XCTAssertNil(VideoAPI.avatarURL(nil))
    }

    @MainActor
    func testNativeDetailSwitchAndBackToHome() throws {
        let browser = BrowserModel()
        browser.navigate("https://youtu.be/sZSlTDlo0Ag")
        XCTAssertFalse(browser.showsHome)
        XCTAssertEqual(browser.videoDetail?.route.id, "sZSlTDlo0Ag")
        browser.navigate("https://youtu.be/4Ui09XbYf1A")
        XCTAssertEqual(browser.videoDetail?.route.id, "4Ui09XbYf1A")
        browser.goBack()
        XCTAssertTrue(browser.showsHome)
        XCTAssertNil(browser.videoDetail)
    }
}
