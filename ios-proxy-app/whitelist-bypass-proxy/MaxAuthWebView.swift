import SwiftUI
import WebKit

struct MaxAuthWebView: UIViewRepresentable {
    let onComplete: (String) -> Void
    @Binding var isPresented: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
        
        // Enable localStorage and cookies
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MaxAuthWebView
        
        init(_ parent: MaxAuthWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inject the cookie parsing script after page loads
            let script = """
            (function() {
                try {
                    var storage = {};
                    for (var i = 0; i < localStorage.length; i++) {
                        var key = localStorage.key(i);
                        storage[key] = localStorage.getItem(key);
                    }
                    window.webkit.messageHandlers.storageHandler.postMessage(JSON.stringify(storage));
                } catch(e) {
                    console.error('Error getting storage:', e);
                }
            })();
            """
            webView.evaluateJavaScript(script)
        }
    }
}

struct MaxAuthSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var cookiesText = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var conferenceId = ""
    @State private var showConferenceId = false
    
    let onComplete: (String) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("MAX.ru Cookies"), footer: Text("Paste LocalStorage JSON from web.max.ru")) {
                    TextEditor(text: $cookiesText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                }
                
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
                
                if showConferenceId && !conferenceId.isEmpty {
                    Section(header: Text("Conference Created"), footer: Text("ID copied to clipboard")) {
                        HStack {
                            Text(conferenceId)
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Button(action: {
                                UIPasteboard.general.string = conferenceId
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                    }
                }
                
                Section {
                    Button(action: parseAndCreateCall) {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                            Text(isLoading ? "Creating..." : "Create Call")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .disabled(cookiesText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
            .navigationTitle("MAX.ru Authorization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func parseAndCreateCall() {
        isLoading = true
        errorMessage = ""
        showConferenceId = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Parse the cookies JSON
                guard let data = cookiesText.data(using: .utf8) else {
                    throw NSError(domain: "Invalid JSON", code: 0)
                }
                
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    throw NSError(domain: "Invalid JSON structure", code: 0)
                }
                
                // Extract __oneme_auth
                guard let onemeAuthStr = json["__oneme_auth"] as? String else {
                    throw NSError(domain: "Missing __oneme_auth", code: 0)
                }
                
                // Parse nested __oneme_auth JSON
                guard let authData = onemeAuthStr.data(using: .utf8) else {
                    throw NSError(domain: "Invalid __oneme_auth encoding", code: 0)
                }
                
                guard let authJson = try JSONSerialization.jsonObject(with: authData, options: []) as? [String: Any] else {
                    throw NSError(domain: "Invalid __oneme_auth JSON", code: 0)
                }
                
                guard let token = authJson["token"] as? String else {
                    throw NSError(domain: "Missing token in __oneme_auth", code: 0)
                }
                
                guard let viewerId = authJson["viewerId"] as? Int else {
                    throw NSError(domain: "Missing viewerId in __oneme_auth", code: 0)
                }
                
                // Extract __oneme_calls_auth_token
                guard let callsAuthToken = json["__oneme_calls_auth_token"] as? String else {
                    throw NSError(domain: "Missing __oneme_calls_auth_token", code: 0)
                }
                
                // Extract device IDs
                let deviceId = json["__oneme_device_id"] as? String ?? UUID().uuidString
                let tracerDeviceId = json["tracer-device-id"] as? String ?? UUID().uuidString
                
                // Create the call
                let result = try createMaxCall(
                    token: token,
                    viewerId: viewerId,
                    callsAuthToken: callsAuthToken,
                    deviceId: deviceId,
                    tracerDeviceId: tracerDeviceId
                )
                
                DispatchQueue.main.async {
                    self.conferenceId = result
                    self.showConferenceId = true
                    self.isLoading = false
                    UIPasteboard.general.string = result
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func createMaxCall(token: String, viewerId: Int, callsAuthToken: String, deviceId: String, tracerDeviceId: String) throws -> String {
        let session = URLSession.shared
        
        // Build cookies string
        let cookies = [
            "__oneme-persistent-cache-enabled=false",
            "__oneme_locale=en",
            "__oneme_auth=\(urlEncode(onemeAuthJSON(token: token, viewerId: viewerId)))",
            "__server_config_overrides={}",
            "oneme_theme={\"colorScheme\":\"system\",\"colorTheme\":\"space\"}",
            "__oneme_device_id=\(deviceId)",
            "tracer-device-id=\(tracerDeviceId)",
            "__oneme_aside_width=393",
            "__oneme_informer={\"lastShowedBannerId\":null,\"banners\":{}}",
            "_okcls_uuid=\"\\(UUID().uuidString)\"",
            "__oneme_calls_auth_token=\(callsAuthToken)"
        ].joined(separator: "; ")
        
        // Generate random device ID for OK.ru
        let okDeviceId = "\(Int64.random(in: 0..<9_000_000_000_000_000_000))"
        
        // Prepare OK.ru anonymLogin request
        let sessionData: [String: Any] = [
            "version": 2,
            "device_id": okDeviceId,
            "client_version": "5.166",
            "client_type": "WEB"
        ]
        
        guard let sessionDataStr = try? JSONSerialization.data(withJSONObject: sessionData),
              let sessionDataEncoded = String(data: sessionDataStr, encoding: .utf8) else {
            throw NSError(domain: "Failed to encode session data", code: 0)
        }
        
        let apiURL = "https://calls.okcdn.ru/fb.do"
        guard let url = URL(string: apiURL) else {
            throw NSError(domain: "Invalid URL", code: 0)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://web.max.ru", forHTTPHeaderField: "Origin")
        request.setValue("https://web.max.ru/", forHTTPHeaderField: "Referer")
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        
        let body = [
            "method": "auth.anonymLogin",
            "session_data": sessionDataEncoded,
            "application_key": "O738Lb2eT6gYv2w8",
            "format": "json"
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
         .joined(separator: "&")
        
        request.httpBody = body.data(using: .utf8)
        
        // First request: auth.anonymLogin
        let group = DispatchGroup()
        group.enter()
        
        var sessionKey = ""
        var authError: Error?
        
        let task = session.dataTask(with: request) { data, response, error in
            defer { group.leave() }
            
            if let error = error {
                authError = error
                return
            }
            
            guard let data = data else {
                authError = NSError(domain: "No data received", code: 0)
                return
            }
            
            guard let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                authError = NSError(domain: "Invalid JSON response", code: 0)
                return
            }
            
            sessionKey = jsonResponse["session_key"] as? String ?? ""
            if sessionKey.isEmpty {
                authError = NSError(domain: "Missing session_key in response", code: 0)
            }
        }
        
        task.resume()
        group.wait()
        
        if let error = authError {
            throw error
        }
        
        // Second request: vchat.joinConversationByLink
        let joinBody = [
            "method": "vchat.joinConversationByLink",
            "session_key": sessionKey,
            "application_key": "O738Lb2eT6gYv2w8",
            "joinLink": "",
            "anonymToken": token,
            "isVideo": "true",
            "isAudio": "false",
            "mediaSettings": "{\"isAudioEnabled\":false,\"isVideoEnabled\":true,\"isScreenSharingEnabled\":false}",
            "format": "json"
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
         .joined(separator: "&")
        
        request.httpBody = joinBody.data(using: .utf8)
        
        group.enter()
        var conferenceId = ""
        var endpoint = ""
        var turnServerData: [String: Any]?
        var joinError: Error?
        
        let joinTask = session.dataTask(with: request) { data, response, error in
            defer { group.leave() }
            
            if let error = error {
                joinError = error
                return
            }
            
            guard let data = data else {
                joinError = NSError(domain: "No data received from join", code: 0)
                return
            }
            
            guard let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                joinError = NSError(domain: "Invalid JSON response from join", code: 0)
                return
            }
            
            conferenceId = jsonResponse["id"] as? String ?? ""
            endpoint = jsonResponse["endpoint"] as? String ?? ""
            turnServerData = jsonResponse["turn_server"] as? [String: Any]
            
            if conferenceId.isEmpty {
                joinError = NSError(domain: "Missing conference ID in response", code: 0)
            }
        }
        
        joinTask.resume()
        group.wait()
        
        if let error = joinError {
            throw error
        }
        
        // WebSocket connection would be established here
        // For now, we just return the conference ID
        print("Conference created: \(conferenceId)")
        print("Endpoint: \(endpoint)")
        
        return conferenceId
    }
    
    private func urlEncode(_ str: String) -> String {
        return str.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? str
    }
    
    private func onemeAuthJSON(token: String, viewerId: Int) -> String {
        let dict: [String: Any] = ["token": token, "viewerId": viewerId]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }
}
