import SwiftUI
import WebKit
import AVFoundation

@main struct WordTrainerApp: App {
    init() { try? AVAudioSession.sharedInstance().setCategory(.playback) } // sound even in silent mode
    var body: some Scene { WindowGroup { Web().ignoresSafeArea() } }
}

struct Web: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.navigationDelegate = context.coordinator
        v.uiDelegate = context.coordinator
        v.scrollView.contentInsetAdjustmentBehavior = .never
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        v.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return v
    }
    func updateUIView(_ v: WKWebView, context: Context) {}

    // Web links (lessons, BBC, British Council) open in Safari, not inside the app.
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = a.request.url, ["http", "https"].contains(u.scheme ?? ""), a.navigationType == .linkActivated {
                UIApplication.shared.open(u); return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }
        func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures f: WKWindowFeatures) -> WKWebView? {
            if let u = a.request.url { UIApplication.shared.open(u) }
            return nil
        }
    }
}
