import Foundation
import WebKit

class WebViewManager: NSObject {
    var tunnelMode: TunnelMode = .dc
    
    private weak var webView: WKWebView?
    private let onLog: (String) -> Void
    private let onStatus: (VpnStatus) -> Void
    private var callUrl = ""
    
    private lazy var hooks: [HookKey: String] = {
        return [
            HookKey(isPion: false, platform: .vk): loadAsset("dc-joiner-vk.js"),
            HookKey(isPion: false, platform: .telemost): loadAsset("dc-joiner-telemost.js"),
            HookKey(isPion: true, platform: .vk): loadAsset("video-vk.js"),
            HookKey(isPion: true, platform: .telemost): loadAsset("video-telemost.js")
        ]
    }()
    
    private lazy var autoclickers: [CallPlatform: String] = {
        return [
            .vk: loadAsset("autoclick-vk.js"),
            .telemost: loadAsset("autoclick-telemost.js")
        ]
    }()
    
    private lazy var muteAudioContext: String = loadAsset("mute-audio-context.js")
    
    init(webView: WKWebView, onLog: @escaping (String) -> Void, onStatus: @escaping (VpnStatus) -> Void) {
        self.webView = webView
        self.onLog = onLog
        self.onStatus = onStatus
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }
    
    private func loadAsset(_ name: String) -> String {
        guard let path = Bundle.main.path(forResource: name, ofType: nil),
              let content = try? String(contentsOfFile: path) else {
            return ""
        }
        return content
    }
    
    func loadUrl(_ url: String) {
        callUrl = url
        webView?.load(URLRequest(url: URL(string: url)!))
    }
    
    func loadBlank() {
        callUrl = ""
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
    }
    
    private func hookForPlatform(_ platform: CallPlatform) -> String {
        let key = HookKey(isPion: tunnelMode.isPion, platform: platform)
        return hooks[key] ?? ""
    }
}

extension WebViewManager: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString, !url.contains("about:blank") else { return }
        
        // Inject mute audio context
        webView.evaluateJavaScript(muteAudioContext)
        
        // Check if hook already installed
        webView.evaluateJavaScript("!!window.__hookInstalled") { [weak self] result, error in
            guard let self = self else { return }
            
            if result as? Bool == true {
                print("Hook already injected, skipping")
                return
            }
            
            let platform = CallPlatform.fromUrl(url)
            self.onLog("Page loaded, injecting hook for \(self.maskUrl(url))")
            
            // Set WebSocket port
            let wsPortScript = "window.WS_PORT=\(Mobile.activeWsPort())"
            webView.evaluateJavaScript(wsPortScript)
            
            // Inject hook
            webView.evaluateJavaScript(self.hookForPlatform(platform))
            
            // Inject autoclick
            if let autoclick = self.autoclickers[platform] {
                self.onLog("Injecting autoclick for \(self.maskUrl(url))")
                webView.evaluateJavaScript(autoclick)
            }
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url?.absoluteString else {
            return .allow
        }
        
        let platform = CallPlatform.fromUrl(url)
        if platform == .telemost && url.contains("/j/") && navigationAction.request.httpMethod == "GET" {
            // CSP stripping would require custom URL loading
        }
        
        return .allow
    }
}

extension WebViewManager: WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

private struct HookKey: Hashable {
    let isPion: Bool
    let platform: CallPlatform
}

private extension WebViewManager {
    func maskUrl(_ url: String) -> String {
        if url.contains("vk.com") {
            return "vk.com/call/****"
        } else if url.contains("tm.me") || url.contains("t.me") {
            return "tm.me/j/****"
        }
        return url
    }
}
