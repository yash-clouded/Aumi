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

    // MARK: - Receiver (Android -> Mac)
    
    private var activeDownloads = [String: FileHandle]()

    func handleInit(fileId: String, name: String, size: Int64) {
        let downloadsFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsFolder.appendingPathComponent(name)
        
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            activeDownloads[fileId] = handle
            print("Aumi: Receiving file \(name) (\(size) bytes)")
        }
    }

    func handleChunk(fileId: String, dataBase64: String) {
        guard let handle = activeDownloads[fileId],
              let data = Data(base64Encoded: dataBase64) else { return }
        handle.write(data)
    }

    func handleComplete(fileId: String) {
        if let handle = activeDownloads[fileId] {
            try? handle.close()
            activeDownloads.removeValue(forKey: fileId)
            print("Aumi: File download complete ✅")
        }
    }
}
