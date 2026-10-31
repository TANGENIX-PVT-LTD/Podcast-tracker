import Foundation
import JavaScriptCore
import Testing
@testable import PodcastTracker

@Suite("Streaming playback")
@MainActor
struct StreamingPlaybackTests {
    @Test func validatesVideoAndResumePosition() throws {
        #expect(YouTubeWebView.playerDocument(videoID: "';alert(1)//", startPosition: 0) == nil)
        for position in [-1.0, .nan, .infinity] {
            let html = try #require(YouTubeWebView.playerDocument(videoID: "abcdefghijk", startPosition: position))
            #expect(html.contains("start:0,"))
        }
        let html = try #require(YouTubeWebView.playerDocument(videoID: "abcdefghijk", startPosition: .greatestFiniteMagnitude))
        #expect(html.contains("start:604800,"))
        #expect(html.contains("strict-origin-when-cross-origin"))
        #expect(html.contains("origin:'\(YouTubeWebView.playerOrigin.absoluteString)'"))
        #expect(YouTubeWebView.playerOrigin.scheme == "https")
    }

    @Test func readyStartsPendingPlaybackBeforeAnyVideoMetadataExists() throws {
        let html = try #require(YouTubeWebView.playerDocument(videoID: "abcdefghijk", startPosition: 42))
        let script = try #require(html.components(separatedBy: "<script>").last?.components(separatedBy: "</script>").first)
        let js = try #require(JSContext())
        js.evaluateScript("""
        var window=this, events=[], calls=0, position=0, duration=0, state=-1, options;
        var names=['timeUpdate','durationReady','playStateChange','playerReady','playerError'];
        window.webkit={messageHandlers:{}};
        names.forEach(function(name){window.webkit.messageHandlers[name]={postMessage:function(value){events.push([name,value]);}};});
        function setInterval(){}
        var YT={Player:function(id,config){options=config;
            this.playVideo=function(){calls++;};this.seekTo=function(time){position=time;};
            this.getCurrentTime=function(){return position;};this.getDuration=function(){return duration;};
            this.getPlayerState=function(){return state;};}};
        """)
        js.evaluateScript(script)
        #expect(js.exception == nil)
        js.evaluateScript("window.podTrackioPlay();onYouTubeIframeAPIReady();options.events.onReady();")
        #expect(js.exception == nil)
        #expect(js.evaluateScript("calls")?.toInt32() == 1)
        #expect(js.evaluateScript("events.some(function(e){return e[0]==='playerReady';})")?.toBool() == true)
        #expect(js.evaluateScript("options.playerVars.start")?.toInt32() == 42)
        js.evaluateScript("state=1;duration=120;window.podTrackioSeek(50);options.events.onStateChange();")
        #expect(js.evaluateScript("events.some(function(e){return e[0]==='timeUpdate'&&e[1]===50;})")?.toBool() == true)
        #expect(js.evaluateScript("events.some(function(e){return e[0]==='playStateChange'&&e[1]==='playing';})")?.toBool() == true)
        js.evaluateScript("state=2;options.events.onStateChange();options.events.onError({data:153});")
        #expect(js.evaluateScript("events.some(function(e){return e[0]==='playStateChange'&&e[1]==='paused';})")?.toBool() == true)
        #expect(js.evaluateScript("events.some(function(e){return e[0]==='playerError'&&e[1]==='153';})")?.toBool() == true)
        #expect(js.exception == nil)
    }
}
