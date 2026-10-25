import AVFoundation
import UniformTypeIdentifiers

// Feed AVPlayer through the public resource-loader API so CDN requests carry
// the same HTTP headers as the Bilibili API, including during background play.
final class MediaResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {
    private final class Transfer {
        let loading: AVAssetResourceLoadingRequest
        let start: Int64
        var skip: Int64 = 0
        var remaining: Int?
        init(_ loading: AVAssetResourceLoadingRequest) {
            self.loading = loading
            start = max(0, max(loading.dataRequest?.currentOffset ?? 0, loading.dataRequest?.requestedOffset ?? 0))
            if let data = loading.dataRequest, !data.requestsAllDataToEndOfResource { remaining = max(0, data.requestedLength - Int(max(0, start - data.requestedOffset))) }
        }
    }
    private var transfers: [Int: Transfer] = [:]
    private var tasks: [Int: URLSessionDataTask] = [:]
    private let configuration: URLSessionConfiguration
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)

    init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
        super.init()
    }

    func asset(_ url: URL) -> AVURLAsset {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.scheme = "bilimusic-stream"
        let asset = AVURLAsset(url: components.url!)
        asset.resourceLoader.setDelegate(self, queue: .main)
        return asset
    }

    func close() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll(); transfers.removeAll()
        session.invalidateAndCancel()
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let requested = loadingRequest.request.url, var components = URLComponents(url: requested, resolvingAgainstBaseURL: false) else { return false }
        components.scheme = "https"
        do {
            let url = try BiliPolicy.mediaURL(components.url!.absoluteString)
            let transfer = Transfer(loadingRequest)
            var request = BiliPolicy.request(url)
            if let data = loadingRequest.dataRequest {
                if data.requestsAllDataToEndOfResource { request.setValue("bytes=\(transfer.start)-", forHTTPHeaderField: "Range") }
                else { request.setValue("bytes=\(transfer.start)-\(transfer.start + Int64(max(1, transfer.remaining ?? 1)) - 1)", forHTTPHeaderField: "Range") }
            } else { request.setValue("bytes=0-1", forHTTPHeaderField: "Range") }
            let task = session.dataTask(with: request)
            transfers[task.taskIdentifier] = transfer; tasks[task.taskIdentifier] = task
            task.resume()
            return true
        } catch { loadingRequest.finishLoading(with: error); return true }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        if let id = transfers.first(where: { $0.value.loading === loadingRequest })?.key { tasks[id]?.cancel(); tasks.removeValue(forKey: id); transfers.removeValue(forKey: id) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let transfer = transfers[dataTask.taskIdentifier], let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
        guard (200..<300).contains(http.statusCode) else {
            transfer.loading.finishLoading(with: BiliError.message("音频服务返回 \(http.statusCode)，请重新播放"))
            remove(dataTask); completionHandler(.cancel); return
        }
        if let info = transfer.loading.contentInformationRequest {
            let total = http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) }
            info.contentLength = total ?? max(0, response.expectedContentLength + (http.statusCode == 206 ? transfer.start : 0))
            // These URLs are AAC-in-MP4 tracks. Some official CDNs label them
            // application/octet-stream or video/mp4, which is not a usable
            // audio format hint for AVPlayer's custom resource loader.
            info.contentType = UTType.mpeg4Audio.identifier
            info.isByteRangeAccessSupported = http.statusCode == 206 || http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes"
        }
        if http.statusCode == 200 { transfer.skip = transfer.start }
        if transfer.loading.dataRequest == nil { transfer.loading.finishLoading(); remove(dataTask); completionHandler(.cancel); return }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let transfer = transfers[dataTask.taskIdentifier], let request = transfer.loading.dataRequest else { return }
        var chunk = data
        if transfer.skip > 0 { let skipped = min(chunk.count, Int(transfer.skip)); chunk = Data(chunk.dropFirst(skipped)); transfer.skip -= Int64(skipped) }
        if let remaining = transfer.remaining { chunk = Data(chunk.prefix(remaining)); transfer.remaining = remaining - chunk.count }
        if !chunk.isEmpty { request.respond(with: chunk) }
        if transfer.remaining == 0 { transfer.loading.finishLoading(); remove(dataTask); dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let transfer = transfers[task.taskIdentifier] else { return }
        if let error = error { transfer.loading.finishLoading(with: error) } else { transfer.loading.finishLoading() }
        tasks.removeValue(forKey: task.taskIdentifier); transfers.removeValue(forKey: task.taskIdentifier)
    }

    private func remove(_ task: URLSessionTask) { tasks.removeValue(forKey: task.taskIdentifier); transfers.removeValue(forKey: task.taskIdentifier) }
}
