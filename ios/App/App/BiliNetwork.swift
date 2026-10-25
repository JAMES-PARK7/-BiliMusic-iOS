import Foundation

enum BiliError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

enum BiliPolicy {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    static func matches(_ host: String, _ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
    static func apiURL(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(),
              ["api.bilibili.com", "passport.bilibili.com", "www.bilibili.com", "www.oiapi.net"].contains(host),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else {
            throw BiliError.message("不支持的接口地址")
        }
        return url
    }
    static func mediaURL(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(),
              ["bilivideo.com", "bilivideo.cn", "akamaized.net", "bilibili.com"].contains(where: { matches(host, $0) }),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else {
            throw BiliError.message("音频地址不受支持")
        }
        return url
    }
    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        return request
    }
    static func text(_ value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "" }
        return String(describing: value)
    }
    static func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        return Double(text(value)) ?? 0
    }
}

struct BiliTrack {
    let id: String
    let bvid: String
    let aid: String
    let cid: String
    let title: String
    let artist: String
    let coverURL: String
    let duration: Double
    init?(_ object: [String: Any]) {
        guard let id = object["id"] as? String, !id.isEmpty else { return nil }
        self.id = id
        bvid = object["bvid"] as? String ?? id
        aid = BiliPolicy.text(object["aid"])
        cid = BiliPolicy.text(object["cid"])
        title = object["title"] as? String ?? "未命名歌曲"
        artist = object["artist"] as? String ?? "BiliMusic"
        coverURL = object["coverUrl"] as? String ?? ""
        duration = BiliPolicy.number(object["duration"])
    }
}

actor BiliNetwork {
    static let shared = BiliNetwork()
    private let session: URLSession
    private var bootstrapTask: Task<Void, Never>?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
    }

    func bootstrap() async {
        if bootstrapTask == nil {
            let session = self.session
            bootstrapTask = Task {
                if let url = URL(string: "https://www.bilibili.com") {
                    _ = try? await session.data(for: BiliPolicy.request(url))
                }
            }
        }
        await bootstrapTask?.value
    }

    func requestJSON(_ value: String) async throws -> (Int, Any) {
        let url = try BiliPolicy.apiURL(value)
        if url.host?.hasSuffix("bilibili.com") == true { await bootstrap() }
        let (data, response) = try await session.data(for: BiliPolicy.request(url))
        guard let http = response as? HTTPURLResponse else { throw BiliError.message("网络响应无效") }
        return (http.statusCode, try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    func api(_ path: String, query: [String: String]) async throws -> [String: Any] {
        var url = URLComponents(string: "https://api.bilibili.com" + path)!
        url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        let (status, raw) = try await requestJSON(url.url!.absoluteString)
        guard (200..<300).contains(status), let result = raw as? [String: Any] else { throw BiliError.message("Bilibili 暂时无法连接") }
        guard BiliPolicy.number(result["code"]) == 0 else {
            throw BiliError.message((result["message"] as? String ?? "请求失败") + "，请稍后重试或登录账号")
        }
        guard let data = result["data"] as? [String: Any] else { throw BiliError.message("没有可用的音频数据") }
        return data
    }

    func resolve(_ track: BiliTrack) async throws -> URL {
        var query: [String: String] = [:]
        do {
            let detail = try await api("/x/web-interface/view", query: ["bvid": track.bvid])
            let cid = BiliPolicy.text(detail["cid"])
            guard !cid.isEmpty else { throw BiliError.message("视频没有音频轨道") }
            query = ["bvid": track.bvid, "cid": cid]
        } catch {
            guard !track.aid.isEmpty, !track.cid.isEmpty else { throw error }
            query = ["avid": track.aid, "cid": track.cid]
        }
        query.merge(["qn": "0", "fnver": "0", "fnval": "16", "fourk": "1"]) { old, _ in old }
        let play = try await api("/x/player/playurl", query: query)
        guard let dash = play["dash"] as? [String: Any], let audio = dash["audio"] as? [[String: Any]],
              let best = audio.max(by: { BiliPolicy.number($0["bandwidth"]) < BiliPolicy.number($1["bandwidth"]) }),
              let source = (best["baseUrl"] ?? best["base_url"]) as? String else { throw BiliError.message("此视频没有可用的独立音轨") }
        return try BiliPolicy.mediaURL(source)
    }

    func download(_ track: BiliTrack) async throws -> (URL, Int64) {
        let url = try await resolve(track)
        let (temporary, response) = try await session.download(for: BiliPolicy.request(url))
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw BiliError.message("下载失败，请重试") }
        let directory = try Self.documents()
        let allowed = CharacterSet(charactersIn: "/\\:?*\"<>|\n\r\u{0}")
        let title = String(track.title.components(separatedBy: allowed).joined(separator: "_").prefix(70))
        let id = track.id.components(separatedBy: allowed).joined(separator: "_")
        let file = directory.appendingPathComponent(title + "-" + String(id.prefix(40)) + ".m4a")
        if !FileManager.default.fileExists(atPath: file.path) { try FileManager.default.moveItem(at: temporary, to: file) }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        return (file, (attributes[.size] as? NSNumber)?.int64Value ?? 0)
    }

    static func documents() throws -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BiliMusic", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
