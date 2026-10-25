import Capacitor
import Foundation
import UIKit
import WebKit

@objc(BiliBridgePlugin)
public class BiliBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "BiliBridgePlugin"
    public let jsName = "BiliBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "request", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "login", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sessionStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "logout", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "download", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "files", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "shareFile", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "exportText", returnType: CAPPluginReturnPromise),
    ]
    private var loginController: BiliLoginViewController?

    @objc func request(_ call: CAPPluginCall) {
        guard let url = call.getString("url") else { call.reject("接口地址为空"); return }
        Task {
            do { let (status, object) = try await BiliNetwork.shared.requestJSON(url); call.resolve(["status": status, "data": object]) }
            catch { call.reject(error.localizedDescription) }
        }
    }
    @objc func sessionStatus(_ call: CAPPluginCall) { call.resolve(["isLoggedIn": Self.hasSession()]) }
    private static func hasSession() -> Bool { (HTTPCookieStorage.shared.cookies ?? []).contains { $0.name == "SESSDATA" && BiliPolicy.matches($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")), "bilibili.com") && ($0.expiresDate == nil || $0.expiresDate! > Date()) } }

    @objc func login(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let presenter = self.bridge?.viewController else { call.reject("无法打开登录页面"); return }
            guard self.loginController == nil else { call.reject("登录页面已打开"); return }
            let controller = BiliLoginViewController { [weak self] completed in self?.loginController = nil; call.resolve(["isLoggedIn": completed]) }
            self.loginController = controller
            let navigation = UINavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .fullScreen
            presenter.present(navigation, animated: true)
        }
    }
    @objc func logout(_ call: CAPPluginCall) {
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where BiliPolicy.matches(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")), "bilibili.com") { HTTPCookieStorage.shared.deleteCookie(cookie) }
        DispatchQueue.main.async {
            let store = WKWebsiteDataStore.default().httpCookieStore
            store.getAllCookies { cookies in
                let group = DispatchGroup()
                for cookie in cookies where BiliPolicy.matches(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")), "bilibili.com") { group.enter(); store.delete(cookie) { group.leave() } }
                group.notify(queue: .main) { call.resolve() }
            }
        }
    }
    @objc func download(_ call: CAPPluginCall) {
        guard let object = call.getObject("track"), let track = BiliTrack(object) else { call.reject("歌曲信息不完整"); return }
        Task {
            do { let (file, size) = try await BiliNetwork.shared.download(track); call.resolve(["name": file.lastPathComponent, "size": size]) }
            catch { call.reject(error.localizedDescription) }
        }
    }
    @objc func files(_ call: CAPPluginCall) {
        do {
            let folder = try BiliNetwork.documents()
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]).filter { $0.pathExtension.lowercased() == "m4a" }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let result: [[String: Any]] = try files.map { file in let values = try file.resourceValues(forKeys: [.fileSizeKey]); return ["name": file.lastPathComponent, "size": values.fileSize ?? 0] }
            call.resolve(["files": result])
        } catch { call.reject(error.localizedDescription) }
    }
    @objc func shareFile(_ call: CAPPluginCall) {
        do {
            guard let name = call.getString("name"), name == (name as NSString).lastPathComponent, !name.contains("\\"), !name.contains("\0"), ["m4a", "json"].contains((name as NSString).pathExtension.lowercased()) else { throw BiliError.message("文件名无效") }
            let file = try BiliNetwork.documents().appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { throw BiliError.message("文件不存在") }
            share(file, call: call)
        } catch { call.reject(error.localizedDescription) }
    }
    @objc func exportText(_ call: CAPPluginCall) {
        do {
            guard let content = call.getString("content"), content.utf8.count <= 5_000_000 else { throw BiliError.message("歌单备份过大或为空") }
            _ = try JSONSerialization.jsonObject(with: Data(content.utf8))
            let file = try BiliNetwork.documents().appendingPathComponent("歌单备份-\(Int(Date().timeIntervalSince1970)).json")
            try content.write(to: file, atomically: true, encoding: .utf8)
            share(file, call: call)
        } catch { call.reject(error.localizedDescription) }
    }
    private func share(_ file: URL, call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let presenter = self?.bridge?.viewController else { call.reject("无法打开分享面板"); return }
            let controller = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            controller.popoverPresentationController?.sourceView = presenter.view
            controller.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            controller.completionWithItemsHandler = { _, _, _, error in if let error = error { call.reject(error.localizedDescription) } else { call.resolve() } }
            presenter.present(controller, animated: true)
        }
    }
}

private final class BiliLoginViewController: UIViewController, WKNavigationDelegate {
    private let completion: (Bool) -> Void
    private let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private var finished = false
    init(completion: @escaping (Bool) -> Void) { self.completion = completion; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "登录 Bilibili"
        webView.navigationDelegate = self; view = webView
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(done))
        let group = DispatchGroup()
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where BiliPolicy.matches(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")), "bilibili.com") {
            group.enter(); webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            if let url = URL(string: "https://passport.bilibili.com/h5-app/passport/login") { self?.webView.load(URLRequest(url: url)) }
        }
    }
    @objc private func cancel() { finish(false) }
    @objc private func done() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            var loggedIn = false
            for cookie in cookies where BiliPolicy.matches(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")), "bilibili.com") {
                HTTPCookieStorage.shared.setCookie(cookie)
                if cookie.name == "SESSDATA" { loggedIn = true }
            }
            DispatchQueue.main.async { self?.finish(loggedIn) }
        }
    }
    private func finish(_ success: Bool) { guard !finished else { return }; finished = true; dismiss(animated: true) { self.completion(success) } }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "https" || url.scheme == "about" { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }
}
