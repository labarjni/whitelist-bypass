import NetworkExtension
import os
#if canImport(iosbind)
import iosbind
#endif

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private var tun2socksRunning = false
    private var tunFd: Int32 = -1
    private var socksServerStarted = false
    private var localSocksPort: Int = 1080
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        os_log("PacketTunnelProvider: starting tunnel", log: .default, type: .info)
        
        // Extract settings from options
        let socksPort = options?["socksPort"] as? Int ?? 1080
        let socksUser = options?["socksUser"] as? String ?? ""
        let socksPass = options?["socksPass"] as? String ?? ""
        let mtu = options?["mtu"] as? Int ?? 1500
        localSocksPort = socksPort
        
        os_log("PacketTunnelProvider: socksPort=%d, mtu=%d, user=%{public}@", 
               log: .default, type: .info, socksPort, mtu, socksUser.isEmpty ? "(none)" : socksUser)
        
        // Setup network settings for the tunnel
        let networkSettings = setupNetworkSettings()
        
        // Get file descriptor for the TUN device
        guard let fd = packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 else {
            os_log("PacketTunnelProvider: failed to get TUN fd", log: .default, type: .error)
            completionHandler(NSError(domain: "PacketTunnelProvider", code: 1, 
                userInfo: [NSLocalizedDescriptionKey: "Failed to get TUN file descriptor"]))
            return
        }
        
        self.tunFd = fd
        os_log("PacketTunnelProvider: got tun fd=%d", log: .default, type: .info, fd)
        
        // Apply network settings
        self.packetFlow.setNetworkSettings(networkSettings)
        
        // Start tun2socks in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            #if canImport(iosbind)
            let result = IosbindStartTun2Socks(fd, Int32(mtu), Int32(socksPort), socksUser, socksPass)
            if result != nil {
                os_log("PacketTunnelProvider: tun2socks error: %{public}@", log: .default, type: .error, result!)
                DispatchQueue.main.async {
                    completionHandler(NSError(domain: "PacketTunnelProvider", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "tun2socks failed: \(result!)"]))
                }
                return
            }
            #endif
            
            self.tun2socksRunning = true
            os_log("PacketTunnelProvider: tun2socks started successfully", log: .default, type: .info)
            
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }
    
    private func setupNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        // DNS settings - use system DNS or custom
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        settings.dnsSettings?.searchDomains = nil
        
        // MTU settings
        settings.mtu = NSNumber(value: 1500)
        
        // IPv4 settings - route all traffic through VPN
        let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4Settings
        
        // IPv6 settings - route all traffic through VPN
        let ipv6Settings = NEIPv6Settings(addresses: ["fd00::1"], networkPrefixLengths: [64])
        ipv6Settings.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6Settings
        
        return settings
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log("PacketTunnelProvider: stopping tunnel, reason=%d", log: .default, type: .info, reason.rawValue)
        
        if self.tun2socksRunning {
            #if canImport(iosbind)
            IosbindStopTun2Socks()
            #endif
            self.tun2socksRunning = false
        }
        
        if self.tunFd >= 0 {
            close(self.tunFd)
            self.tunFd = -1
        }
        
        os_log("PacketTunnelProvider: tunnel stopped", log: .default, type: .info)
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from the main app if needed
        os_log("PacketTunnelProvider: received app message, length=%d", log: .default, type: .info, messageData.count)
        completionHandler?(nil)
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        os_log("PacketTunnelProvider: sleep", log: .default, type: .info)
        completionHandler()
    }
    
    override func wake() {
        os_log("PacketTunnelProvider: wake", log: .default, type: .info)
    }
}
