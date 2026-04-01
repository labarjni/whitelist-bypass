import Foundation

class LogWriter {
    private var logs: [String] = []
    private let maxLogs = 1000
    
    func append(_ message: String) {
        logs.append(message)
        if logs.count > maxLogs {
            logs.removeFirst()
        }
    }
    
    func reset() {
        logs.removeAll()
    }
    
    func getLogs() -> String {
        return logs.joined(separator: "\n")
    }
}
