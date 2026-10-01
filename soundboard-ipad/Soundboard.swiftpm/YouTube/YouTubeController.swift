import Foundation
import WebKit

/// Owns the embedded YouTube web view and talks to the injected capture script.
@MainActor
final class YouTubeController: ObservableObject {
    enum CaptureState: Equatable {
        case idle
        case recording(Double)
        case done(String)
        case failed(String)
    }

    static let home = URL(string: "https://www.youtube.com/")!
    static let maxClipSeconds = 120.0

    @Published private(set) var hasVideo = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var adShowing = false
    @Published private(set) var title = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var capture: CaptureState = .idle

    /// Called with the finished WAV, the sound's name and where it came from.
    var onCaptured: ((Data, String, SoundSource) throws -> Void)?

    let webView: WKWebView
    private var pcm = Data()
    private var pendingName = ""

    var isRecording: Bool {
        if case .recording = capture { return true }
        return false
    }

    init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Without a Safari token YouTube serves a reduced page.
        config.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: CaptureScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = content

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        content.add(MessageBridge(self), name: "soundboard")
    }

    // MARK: Navigation

    func goHome() { webView.load(URLRequest(url: Self.home)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let isLink = query.range(
            of: #"^(https?://)?((www|m|music)\.)?(youtube\.com|youtu\.be)/"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let url: URL?
        if isLink {
            url = URL(string: query.lowercased().hasPrefix("http") ? query : "https://\(query)")
        } else {
            var components = URLComponents(string: "https://www.youtube.com/results")!
            components.queryItems = [URLQueryItem(name: "search_query", value: query)]
            url = components.url
        }
        if let url { webView.load(URLRequest(url: url)) }
    }

    // MARK: Playback state

    /// Polls the page for the player's state while the panel is visible.
    func pollLoop() async {
        // YouTube loads the first time the panel is shown.
        if webView.url == nil { goHome() }
        while !Task.isCancelled {
            await poll()
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func poll() async {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        guard !isRecording else { return }
        guard let json = try? await webView.evaluateJavaScript("window.__sb ? window.__sb.state() : ''") as? String,
              let data = json.data(using: .utf8),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            hasVideo = false
            return
        }
        hasVideo = state["hasVideo"] as? Bool ?? false
        currentTime = (state["currentTime"] as? NSNumber)?.doubleValue ?? 0
        duration = (state["duration"] as? NSNumber)?.doubleValue ?? 0
        adShowing = state["ad"] as? Bool ?? false
        title = state["title"] as? String ?? ""
    }

    // MARK: Clipping

    func preview(start: Double, end: Double) {
        webView.evaluateJavaScript("window.__sb && window.__sb.preview(\(start), \(end))", completionHandler: nil)
    }

    func startCapture(start: Double, end: Double, name: String) {
        guard !isRecording else { return }
        pcm = Data()
        pendingName = name
        capture = .recording(0)
        Task {
            let result = try? await webView.evaluateJavaScript("window.__sb ? window.__sb.capture(\(start), \(end)) : 'missing'")
            if (result as? String) != "ok" {
                capture = .failed("This page isn't ready yet. Wait for it to load, then try again.")
            }
        }
    }

    func reportError(_ message: String) {
        capture = .failed(message)
    }

    func cancelCapture() {
        webView.evaluateJavaScript("window.__sb && window.__sb.cancel()", completionHandler: nil)
    }

    fileprivate func handle(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "chunk":
            if let base64 = message["data"] as? String, let chunk = Data(base64Encoded: base64) {
                pcm.append(chunk)
            }
        case "progress":
            guard isRecording else { return }
            capture = .recording((message["fraction"] as? NSNumber)?.doubleValue ?? 0)
            currentTime = (message["time"] as? NSNumber)?.doubleValue ?? currentTime
        case "done":
            let sampleRate = (message["sampleRate"] as? NSNumber)?.intValue ?? 48000
            let channels = (message["channels"] as? NSNumber)?.intValue ?? 2
            let pageTitle = message["title"] as? String ?? ""
            let source = SoundSource(
                title: pageTitle,
                url: message["url"] as? String ?? "",
                start: (message["start"] as? NSNumber)?.doubleValue ?? 0,
                end: (message["end"] as? NSNumber)?.doubleValue ?? 0
            )
            let name = pendingName.isEmpty ? (pageTitle.isEmpty ? "YouTube clip" : pageTitle) : pendingName
            let seconds = Double(pcm.count) / Double(sampleRate * channels * 2)
            let wav = WAV.make(pcm16: pcm, sampleRate: sampleRate, channels: channels)
            pcm = Data()
            do {
                try onCaptured?(wav, name, source)
                capture = .done("Saved “\(name)” (\(String(format: "%.1f", seconds))s).")
            } catch {
                capture = .failed(error.localizedDescription)
            }
        case "error":
            pcm = Data()
            capture = .failed(message["message"] as? String ?? "Capture failed.")
        default:
            break
        }
    }
}

/// Forwards script messages without the user content controller retaining the controller.
private final class MessageBridge: NSObject, WKScriptMessageHandler {
    weak var target: YouTubeController?

    init(_ target: YouTubeController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated {
            target?.handle(body)
        }
    }
}
