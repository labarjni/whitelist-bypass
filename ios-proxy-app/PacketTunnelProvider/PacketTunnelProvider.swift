import NetworkExtension
import os

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private var tun2socksRunning = false
    private var tunFd: Int32 = -1
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        os_log("PacketTunnelProvider: starting tunnel", log: .default, type: .info)
        
        // Get file descriptor for the TUN device
        let packetFlow = self.packetFlow
        guard let fd = packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 else {
            completionHandler(NSError(domain: "PacketTunnelProvider", code: 1, 
                userInfo: [NSLocalizedDescriptionKey: "Failed to get TUN file descriptor"]))
            return
        }
        
        self.tunFd = fd
        
        // Extract settings from options
        let socksPort = options?["socksPort"] as? Int ?? 1080
        let socksUser = options?["socksUser"] as? String ?? ""
        let socksPass = options?["socksPass"] as? String ?? ""
        let mtu = options?["mtu"] as? Int ?? 1500
        
        os_log("PacketTunnelProvider: tun fd=%d, socksPort=%d, mtu=%d", 
               log: .default, type: .info, fd, socksPort, mtu)
        
        // Start tun2socks
        startTun2Socks(fd: Int(fd), mtu: mtu, socksPort: socksPort, 
                       socksUser: socksUser, socksPass: socksPass)
        
        self.tun2socksRunning = true
        
        completionHandler(nil)
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log("PacketTunnelProvider: stopping tunnel, reason=%d", log: .default, type: .info, reason.rawValue)
        
        if self.tun2socksRunning {
            stopTun2Socks()
            self.tun2socksRunning = false
        }
        
        if self.tunFd >= 0 {
            close(self.tunFd)
            self.tunFd = -1
        }
        
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from the main app if needed
        completionHandler?(nil)
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    override func wake() {
        // Wake up from sleep
    }
}

// MARK: - tun2socks bridge

private func startTun2Socks(fd: Int, mtu: Int, socksPort: Int, socksUser: String, socksPass: String) {
    // This will be implemented by calling into the Go library via gomobile
    // For now, we use a placeholder that will be replaced with actual gomobile binding
    #if canImport(iosbind)
    import iosbind
    IosbindStartTun2Socks(Int32(fd), Int32(mtu), Int32(socksPort), socksUser, socksPass)
    #else
    print("tun2socks not available - would start with fd=\(fd), mtu=\(mtu), port=\(socksPort)")
    #endif
}

private func stopTun2Socks() {
    #if canImport(iosbind)
    import iosbind
    IosbindStopTun2Socks()
    #else
    print("tun2socks stop called")
    #endif
}
