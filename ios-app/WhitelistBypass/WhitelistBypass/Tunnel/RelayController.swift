import Foundation

class RelayController {
    private var dcThread: Thread?
    private var pionThread: Thread?
    private var pionProcess: Process?
    
    @volatile var isRunning = false
    
    private let onLog: (String) -> Void
    private let onStatus: (VpnStatus) -> Void
    
    init(onLog: @escaping (String) -> Void, onStatus: @escaping (VpnStatus) -> Void) {
        self.onLog = onLog
        self.onStatus = onStatus
    }
    
    func start(mode: TunnelMode, platform: CallPlatform) {
        stop()
        isRunning = true
        
        if mode.isPion {
            startPion(mode: mode, platform: platform)
        } else {
            startDC()
        }
    }
    
    func stop() {
        isRunning = false
        
        pionProcess?.terminate()
        pionProcess = nil
        pionThread = nil
        
        // Stop DC relay via Mobile library
        Mobile.stopJoiner()
        dcThread = nil
    }
    
    private func startDC() {
        let cb = LogCallbackImpl { [weak self] msg in
            self?.onLog(msg)
            if msg.contains("browser connected") {
                self?.onStatus(.tunnelActive)
            } else if msg.contains("ws read error") {
                self?.onStatus(.tunnelLost)
            }
        }
        
        dcThread = Thread { [weak self] in
            guard let self = self else { return }
            do {
                try Mobile.startJoiner(wsPort: Ports.dcWs, socksPort: Ports.socks, cb: cb)
            } catch {
                if self.isRunning {
                    self.onLog("Relay error: \(error.localizedDescription)")
                }
            }
        }
        dcThread?.start()
        onLog("Relay started DC mode (SOCKS5 :\(Ports.socks), WS :\(Ports.dcWs))")
    }
    
    private func startPion(mode: TunnelMode, platform: CallPlatform) {
        // Find the relay binary in the app bundle
        guard let relayPath = Bundle.main.path(forResource: "relay", ofType: nil) else {
            onLog("Pion relay binary not found")
            return
        }
        
        let relayMode = mode.relayMode(for: platform)
        
        pionThread = Thread { [weak self] in
            guard let self = self else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: relayPath)
            process.arguments = [
                "--mode", relayMode,
                "--ws-port", "\(Ports.pionSignaling)",
                "--socks-port", "\(Ports.socks)"
            ]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                self.pionProcess = process
                self.onLog("Pion relay started mode=\(relayMode) (signaling :\(Ports.pionSignaling), SOCKS5 :\(Ports.socks))")
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    for line in output.split(separator: "\n") {
                        let lineStr = String(line)
                        print("RELAY: \(lineStr)")
                        self.onLog(lineStr)
                        if lineStr.contains("CONNECTED") {
                            self.onStatus(.tunnelActive)
                        } else if lineStr.contains("session cleaned up") {
                            self.onStatus(.tunnelLost)
                        }
                    }
                }
                
                self.onLog("Pion relay exited: \(process.terminationStatus)")
            } catch {
                if self.isRunning {
                    print("Pion relay error: \(error)")
                    self.onLog("Pion relay error: \(error.localizedDescription)")
                }
            }
        }
        pionThread?.start()
    }
}

// Wrapper for Go LogCallback interface
class LogCallbackImpl: NSObject, LogCallback {
    let handler: (String) -> Void
    
    init(handler: @escaping (String) -> Void) {
        self.handler = handler
        super.init()
    }
    
    func onLog(_ msg: String?) {
        if let msg = msg {
            handler(msg)
        }
    }
}
