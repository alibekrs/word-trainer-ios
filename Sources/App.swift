import SwiftUI
import WebKit

@main struct WordTrainerApp: App {
    var body: some Scene { WindowGroup { Web().ignoresSafeArea() } }
}

struct Web: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView()
        v.scrollView.contentInsetAdjustmentBehavior = .never
        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        v.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return v
    }
    func updateUIView(_ v: WKWebView, context: Context) {}
}
