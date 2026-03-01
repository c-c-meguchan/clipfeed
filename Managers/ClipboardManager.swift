import AppKit
import Combine

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var currentContent: String = ""
    @Published var changeCount: Int = 0
    
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    
    private init() {
        lastChangeCount = pasteboard.changeCount
        startPolling()
    }
    
    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkClipboard() {
        let currentChangeCount = pasteboard.changeCount
        
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            
            if let string = pasteboard.string(forType: .string) {
                currentContent = string
                changeCount = currentChangeCount
            }
        }
    }
    
    func getCurrentContent() -> String? {
        return pasteboard.string(forType: .string)
    }
}
