import UIKit
import WebKit

class MainViewController: UIViewController {
    
    private var urlInput: UITextField!
    private var goButton: UIButton!
    private var logView: UITextView!
    private var webView: WKWebView!
    private var toggleButton: UIButton!
    private var gearButton: UIButton!
    private var statusBar: UILabel!
    
    private var relay: RelayController!
    private var webViewManager: WebViewManager!
    
    private var isWebViewExpanded = false
    private var previousUrl = ""
    private var tunnelMode: TunnelMode = .dc
    
    private let logWriter = LogWriter()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        relay = RelayController(
            onLog: { [weak self] msg in
                self?.appendLog(msg)
            },
            onStatus: { [weak self] status in
                self?.updateStatus(status)
            }
        )
        
        webViewManager = WebViewManager(
            webView: webView,
            onLog: { [weak self] msg in
                self?.appendLog(msg)
            },
            onStatus: { [weak self] status in
                self?.updateStatus(status)
            }
        )
        
        loadPreviousUrl()
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        
        // Status bar
        statusBar = UILabel()
        statusBar.text = "Idle"
        statusBar.font = .systemFont(ofSize: 14, weight: .medium)
        statusBar.textAlignment = .center
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)
        
        // URL input
        urlInput = UITextField()
        urlInput.placeholder = "Paste call link here..."
        urlInput.borderStyle = .roundedRect
        urlInput.font = .systemFont(ofSize: 16)
        urlInput.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(urlInput)
        
        // Clear button
        let clearButton = UIButton(type: .system)
        clearButton.setTitle("✕", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 18)
        clearButton.addTarget(self, action: #selector(clearUrl), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clearButton)
        
        // Go button
        goButton = UIButton(type: .system)
        goButton.setTitle("GO", for: .normal)
        goButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        goButton.backgroundColor = .systemBlue
        goButton.setTitleColor(.white, for: .normal)
        goButton.layer.cornerRadius = 8
        goButton.addTarget(self, action: #selector(goPressed), for: .touchUpInside)
        goButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(goButton)
        
        // Gear button (settings)
        gearButton = UIButton(type: .system)
        gearButton.setTitle("⚙️", for: .normal)
        gearButton.titleLabel?.font = .systemFont(ofSize: 20)
        gearButton.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        gearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gearButton)
        
        // Toggle WebView button
        toggleButton = UIButton(type: .system)
        toggleButton.setTitle("Show WebView", for: .normal)
        toggleButton.titleLabel?.font = .systemFont(ofSize: 14)
        toggleButton.addTarget(self, action: #selector(toggleWebView), for: .touchUpInside)
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toggleButton)
        
        // Log view
        logView = UITextView()
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.isEditable = false
        logView.layer.borderColor = UIColor.lightGray.cgColor
        logView.layer.borderWidth = 1
        logView.layer.cornerRadius = 4
        logView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logView)
        
        // WebView container
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isHidden = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        
        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            urlInput.topAnchor.constraint(equalTo: statusBar.bottomAnchor, constant: 16),
            urlInput.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            urlInput.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            urlInput.heightAnchor.constraint(equalToConstant: 40),
            
            clearButton.centerYAnchor.constraint(equalTo: urlInput.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: gearButton.leadingAnchor, constant: -8),
            clearButton.widthAnchor.constraint(equalToConstant: 30),
            
            gearButton.centerYAnchor.constraint(equalTo: urlInput.centerYAnchor),
            gearButton.trailingAnchor.constraint(equalTo: goButton.leadingAnchor, constant: -8),
            gearButton.widthAnchor.constraint(equalToConstant: 40),
            
            goButton.centerYAnchor.constraint(equalTo: urlInput.centerYAnchor),
            goButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            goButton.widthAnchor.constraint(equalToConstant: 60),
            goButton.heightAnchor.constraint(equalToConstant: 40),
            
            toggleButton.topAnchor.constraint(equalTo: urlInput.bottomAnchor, constant: 8),
            toggleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            logView.topAnchor.constraint(equalTo: toggleButton.bottomAnchor, constant: 8),
            logView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            logView.heightAnchor.constraint(equalToConstant: 150),
            
            webView.topAnchor.constraint(equalTo: logView.bottomAnchor, constant: 8),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadPreviousUrl() {
        if let savedUrl = UserDefaults.standard.string(forKey: "lastUrl"), !savedUrl.isEmpty {
            urlInput.text = savedUrl
            previousUrl = savedUrl
        }
    }
    
    @objc private func clearUrl() {
        urlInput.text = ""
    }
    
    @objc private func goPressed() {
        guard let urlText = urlInput.text?.trimmingCharacters(in: .whitespaces), !urlText.isEmpty else {
            return
        }
        
        logWriter.reset()
        relay.stop()
        
        let platform = CallPlatform.fromUrl(urlText)
        relay.start(mode: tunnelMode, platform: platform)
        
        urlInput.resignFirstResponder()
        updateStatus(.connecting)
        appendLog("Loading: \(maskUrl(urlText))")
        
        if previousUrl != urlText {
            previousUrl = urlText
            UserDefaults.standard.set(urlText, forKey: "lastUrl")
        }
        
        webViewManager.loadUrl(urlText)
    }
    
    @objc private func toggleWebView() {
        isWebViewExpanded.toggle()
        webView.isHidden = !isWebViewExpanded
        toggleButton.setTitle(isWebViewExpanded ? "Hide WebView" : "Show WebView", for: .normal)
    }
    
    @objc private func showSettings() {
        showTunnelModeSelector()
    }
    
    private func showTunnelModeSelector() {
        let alert = UIAlertController(title: "Tunnel Mode", message: "Select tunnel mode", preferredStyle: .actionSheet)
        
        for mode in TunnelMode.allCases {
            alert.addAction(UIAlertAction(title: mode.rawValue, style: .default) { [weak self] _ in
                self?.tunnelMode = mode
                self?.webViewManager.tunnelMode = mode
                self?.fullReset()
            })
        }
        
        alert.addAction(UIAlertAction(title: "Clear Logs", style: .default) { [weak self] _ in
            self?.logWriter.reset()
            self?.logView.text = ""
        })
        
        alert.addAction(UIAlertAction(title: "Share Logs", style: .default) { [weak self] _ in
            self?.shareLogs()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func shareLogs() {
        let logs = logWriter.getLogs()
        let vc = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
        present(vc, animated: true)
    }
    
    private func fullReset() {
        resetState()
        VpnManager.shared.stopVPN()
    }
    
    private func resetState() {
        relay.stop()
        webViewManager.loadBlank()
        logWriter.reset()
        updateStatus(.idle)
    }
    
    private func updateStatus(_ status: VpnStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.statusBar.text = status.rawValue
            if status == .tunnelActive {
                self?.startVPN()
            }
        }
    }
    
    private func startVPN() {
        appendLog("Tunnel ready, starting VPN...")
        VpnManager.shared.startVPN { [weak self] status in
            self?.updateStatus(status)
        }
    }
    
    private func appendLog(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.logWriter.append(message)
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self?.logView.text += "[\(timestamp)] \(message)\n"
            self?.logView.scrollRangeToVisible(NSRange(location: self?.logView.text.count ?? 0, length: 0))
        }
    }
    
    private func maskUrl(_ url: String) -> String {
        if url.contains("vk.com") {
            return "vk.com/call/****"
        } else if url.contains("tm.me") || url.contains("t.me") {
            return "tm.me/j/****"
        }
        return url
    }
}

extension MainViewController: WKNavigationDelegate, WKUIDelegate {
    // WebView delegate methods handled by WebViewManager
}
