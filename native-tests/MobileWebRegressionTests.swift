import UIKit
import WebKit
import XCTest

@MainActor
final class MobileWebRegressionTests: XCTestCase {
    private var web: WKWebView!
    private var window: UIWindow!

    private func openWeb() async throws {
        let root = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Web")!.deletingLastPathComponent()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(TestAssets(root: root), forURLScheme: "bilimusic-test")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.mockResponses, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 393, height: 852), configuration: configuration)
        window = UIWindow(frame: web.frame)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(web)
        window.makeKeyAndVisible()
        web.load(URLRequest(url: URL(string: "bilimusic-test://localhost/#/search")!))
        try await waitFor("document.querySelector('form[role=search] input[type=search]') !== null")
    }

    private func closeWeb() {
        web?.stopLoading(); web?.removeFromSuperview(); window?.isHidden = true
        web = nil; window = nil
    }

    func testSearchFormShowsResultsAndAnUnavailableServiceShowsAnError() async throws {
        defer { closeWeb() }
        try await openWeb()
        try await submit("周杰伦")
        try await waitFor("document.querySelector('.apple-search-list')?.textContent.includes('晴天') === true")
        let keyboardHint = try await web.evaluateJavaScript("document.querySelector('input[type=search]').getAttribute('enterkeyhint')") as? String
        XCTAssertEqual(keyboardHint, "search")
        try await submit("network-error")
        try await waitFor("document.querySelector('[role=alert]')?.textContent.includes('重试搜索') === true")
    }

    func testLyricsHaveReadableContrastInLightAndDarkThemes() async throws {
        defer { closeWeb() }
        try await openWeb()
        _ = try await web.evaluateJavaScript("document.querySelector('.mobile-current').click(); true")
        try await waitFor("document.querySelector('.mobile-player-actions button') !== null")
        _ = try await web.evaluateJavaScript("document.querySelector('.mobile-player-actions button').click(); true")
        try await waitFor("document.querySelector('.mobile-lyrics .lyrics-line[aria-current=true]') !== null")
        try await Task.sleep(nanoseconds: 700_000_000)
        for theme in ["light", "dark"] {
            _ = try await web.evaluateJavaScript("document.documentElement.dataset.theme = '\(theme)'; true")
            let ratio = try await web.evaluateJavaScript(Self.contrastRatio) as! Double
            XCTAssertGreaterThanOrEqual(ratio, 3, "Large active lyrics must be legible in \(theme) mode")
        }
        let noBlur = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.lyrics-line')).filter === 'none' || getComputedStyle(document.querySelector('.lyrics-line')).filter === 'blur(0px)'") as? Bool
        XCTAssertEqual(noBlur, true)
    }

    private func submit(_ keyword: String) async throws {
        let encoded = String(data: try JSONSerialization.data(withJSONObject: [keyword]), encoding: .utf8)!
        _ = try await web.evaluateJavaScript("(() => { const field = document.querySelector('input[type=search]'); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(field, \(encoded)[0]); field.dispatchEvent(new Event('input', {bubbles:true})); return true; })()")
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = try await web.evaluateJavaScript("document.querySelector('form[role=search]').requestSubmit(); true")
    }

    private func waitFor(_ condition: String) async throws {
        for _ in 0..<150 {
            if (try? await web.evaluateJavaScript("Boolean(\(condition))")) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let errors = (try? await web.evaluateJavaScript("JSON.stringify(window.__webTestErrors || [])")) as? String ?? "[]"
        XCTFail("Timed out waiting for: " + condition + "; JavaScript errors: " + errors)
        throw NSError(domain: "MobileWebRegressionTests", code: 1)
    }

    private static let contrastRatio = """
    (() => {
      const line = document.querySelector('.mobile-lyrics .lyrics-line[aria-current=true]');
      const color = getComputedStyle(line).color;
      const background = getComputedStyle(document.querySelector('.mobile-now-playing')).backgroundColor;
      const lum = text => text.match(/[\\d.]+/g).slice(0,3).map(Number).map(x => { x/=255; return x<=0.04045 ? x/12.92 : ((x+0.055)/1.055)**2.4 }).reduce((sum,x,i) => sum+x*[0.2126,0.7152,0.0722][i],0);
      const a=lum(color), b=lum(background); return (Math.max(a,b)+0.05)/(Math.min(a,b)+0.05);
    })()
    """

    private static let mockResponses = """
    (() => {
      window.__webTestErrors=[];
      window.addEventListener('error',event=>window.__webTestErrors.push(event.message));
      window.addEventListener('unhandledrejection',event=>window.__webTestErrors.push(String(event.reason)));
      const track = {id:'BV-test',bvid:'BV-test',title:'AIYOU',artist:'Eve',duration:164,coverUrl:'',videoUrl:'',playCount:0,isLiked:false};
      localStorage.setItem('bilimusic_player_state',JSON.stringify({queue:[track],currentTrack:track,progress:0,volume:80,isMuted:false,repeatMode:'none',isShuffled:false}));
      const lyric = {lines:[{time:0,text:'第一行清晰可见的歌词'},{time:10,text:'第二行歌词也可以阅读'},{time:20,text:'第三行歌词'}],synced:true,instrumental:false,trackName:'AIYOU',artistName:'Eve',sourceId:'fixture'};
      localStorage.setItem('bilimusic_lyrics_v2',JSON.stringify({'BV-test':{status:'ok',result:lyric}}));
      window.fetch = async address => {
        const url = new URL(String(address),location.href);
        let value = {code:0,data:{}};
        if(url.pathname.endsWith('/nav')) value={code:0,data:{isLogin:false,wbi_img:{img_url:'https://i0.hdslb.com/0123456789abcdef0123456789abcdef.png',sub_url:'https://i0.hdslb.com/fedcba9876543210fedcba9876543210.png'}}};
        else if(url.pathname.endsWith('/search/type')) value=url.searchParams.get('keyword')==='network-error'?{code:-412,message:'搜索服务暂不可用'}:{code:0,data:{numResults:1,numPages:1,result:[{bvid:'BV-search',aid:1,title:'周杰伦 - 晴天',author:'音乐人',play:1,duration:'4:10',pic:''}]}};
        return new Response(JSON.stringify(value),{status:200,headers:{'Content-Type':'application/json'}});
      };
    })();
    """
}

private final class TestAssets: NSObject, WKURLSchemeHandler {
    private let root: URL
    init(root: URL) { self.root = root }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let url = urlSchemeTask.request.url!
        let path = url.path == "/" || url.path.isEmpty ? "index.html" : String(url.path.dropFirst())
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else { urlSchemeTask.didFailWithError(NSError(domain: "TestAssets", code: 404)); return }
        let mime = ["html":"text/html", "js":"text/javascript", "css":"text/css", "png":"image/png", "svg":"image/svg+xml"][file.pathExtension] ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":mime, "Access-Control-Allow-Origin":"*"])!
        urlSchemeTask.didReceive(response); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
