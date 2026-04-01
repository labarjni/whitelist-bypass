import Foundation
import NetworkExtension

class VpnManager: NSObject {
    static let shared = VpnManager()
    
    private var manager: NEVPNManager?
    private var tunnelProviderManager: NETunnelProviderManager?
    
    var isConnected: Bool {
        return manager?.connection.status == .connected || 
               tunnelProviderManager?.connection.status == .connected ?? false
    }
    
    var onDisconnect: (() -> Void)?
    
    override init() {
        super.init()
        loadVPNConfiguration()
    }
    
    func loadVPNConfiguration() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let managers = managers, !managers.isEmpty {
                self?.tunnelProviderManager = managers.first
            } else {
                self?.createVPNConfiguration()
            }
        }
    }
    
    private func createVPNConfiguration() {
        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol(
            providerBundleIdentifier: "com.whitelist.bypass.tunnel-extension",
            providerConfiguration: ["socksPort": Ports.socks]
        )
        proto.serverAddress = "127.0.0.1"
        manager.protocolConfiguration = proto
        manager.localizedDescription = "Whitelist Bypass VPN"
        manager.isEnabled = true
        self.tunnelProviderManager = manager
        
        manager.saveToPreferences { [weak self] error in
            if let error = error {
                print("VPN save error: \(error)")
            } else {
                self?.loadVPNConfiguration()
            }
        }
    }
    
    func startVPN(status: @escaping (VpnStatus) -> Void) {
        guard let manager = tunnelProviderManager else {
            print("VPN manager not configured")
            return
        }
        
        do {
            try manager.connection.startVPNTunnel(options: [
                "socksPort": NSNumber(value: Ports.socks)
            ])
            status(.connecting)
        } catch {
            print("VPN start error: \(error)")
        }
    }
    
    func stopVPN() {
        tunnelProviderManager?.connection.stopVPNTunnel()
    }
    
    func updateStatus(_ newStatus: VpnStatus) {
        // Status updates handled by UI
    }
}
