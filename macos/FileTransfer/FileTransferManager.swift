import Foundation

/**
 * Handles outgoing file transfers from Mac to Android.
 * Chunks files into 64KB AES-encrypted frames to minimize memory usage.
 */
class AumiFileTransferManager {
    static let shared = AumiFileTransferManager()
    
    private let chunkSize = 64 * 1024 // 64 KB
    
    /**
     * Starts a chunked file transfer.
     */
    func sendFile(url: URL) {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return }
        
        let fileId   = UUID().uuidString
        let fileName = url.lastPathComponent
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        
        // 1. Send Init
        ConnectionManager.shared.sendControl([
            "type": "FILE_TRANSFER_INIT",
            "fileId": fileId,
            "fileName": fileName,
            "fileSize": Int64(fileSize)
        ])
        
        // 2. Stream Chunks
        DispatchQueue.global(qos: .utility).async {
            while true {
                let data = fileHandle.readData(ofLength: self.chunkSize)
                if data.isEmpty { break }
                
                ConnectionManager.shared.sendControl([
                    "type": "FILE_TRANSFER_CHUNK",
                    "fileId": fileId,
                    "data": data.base64EncodedString()
                ])
                
                // Throttle slightly to not overwhelm the TCP buffer on consumer devices
                Thread.sleep(forTimeInterval: 0.005)
            }
            
            // 3. Send Complete
            ConnectionManager.shared.sendControl([
                "type": "FILE_TRANSFER_COMPLETE",
                "fileId": fileId
            ])
            
            try? fileHandle.close()
        }
    }
}
