import Foundation

enum TunnelMode: String, CaseIterable {
    case dc = "DC"
    case pionVK = "Pion VK"
    case pionTelemost = "Pion Telemost"
    
    var isPion: Bool {
        switch self {
        case .dc: return false
        case .pionVK, .pionTelemost: return true
        }
    }
    
    func relayMode(for platform: CallPlatform) -> String {
        switch (self, platform) {
        case (.dc, _): return ""
        case (.pionVK, .vk): return "vk-video-joiner"
        case (.pionVK, .telemost): return "vk-video-joiner"
        case (.pionTelemost, .telemost): return "telemost-video-joiner"
        case (.pionTelemost, .vk): return "telemost-video-joiner"
        }
    }
}

enum CallPlatform: String {
    case vk = "VK"
    case telemost = "Telemost"
    
    static func fromUrl(_ url: String) -> CallPlatform {
        if url.contains("vk.com") || url.contains("vk.vk") {
            return .vk
        } else if url.contains("tm.me") || url.contains("t.me") {
            return .telemost
        }
        return .vk // default
    }
}

enum VpnStatus: String {
    case idle = "Idle"
    case connecting = "Connecting"
    case callConnected = "Call Connected"
    case datachannelOpen = "DataChannel Open"
    case tunnelActive = "Tunnel Active"
    case tunnelLost = "Tunnel Lost"
    case datachannelLost = "DataChannel Lost"
    case callDisconnected = "Call Disconnected"
    case callFailed = "Call Failed"
}

struct Ports {
    static let socks: Int32 = 1080
    static let dcWs: Int32 = 9000
    static let pionSignaling: Int32 = 9001
}
