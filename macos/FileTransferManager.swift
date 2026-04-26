import Foundation

class AumiFileTransferManager {
    static let shared = AumiFileTransferManager()
    
    private var activeTransfers: [String: FileTransferSession] = [:]
    
    struct FileTransferSession {
        let fileId: String
        let fileName: String
        let totalSize: Int64
        var receivedSize: Int64 = 0
        let tempURL: URL
        let fileHandle: FileHandle
    }
    
    func handleInit(fileId: String, name: String, size: Int64) {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(fileId)
        
        FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
        guard let handle = try? FileHandle(forWritingTo: tempURL) else { return }
        
        activeTransfers[fileId] = FileTransferSession(
            fileId: fileId,
            fileName: name,
            totalSize: size,
            tempURL: tempURL,
            fileHandle: handle
        )
        print("Started file transfer: \(name) (\(size) bytes)")
    }
    
    func handleChunk(fileId: String, dataBase64: String) {
        guard var session = activeTransfers[fileId],
              let data = Data(base64Encoded: dataBase64) else { return }
        
        session.fileHandle.write(data)
        session.receivedSize += Int64(data.count)
        activeTransfers[fileId] = session
        
        let progress = Float(session.receivedSize) / Float(session.totalSize)
        print("File progress: \(Int(progress * 100))%")
    }
    
    func handleComplete(fileId: String) {
        guard let session = activeTransfers[fileId] else { return }
        
        session.fileHandle.closeFile()
        
        // Move to Downloads
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let finalURL = downloads.appendingPathComponent(session.fileName)
        
        try? FileManager.default.moveItem(at: session.tempURL, to: finalURL)
        print("File transfer complete: \(finalURL.path)")
        activeTransfers.removeValue(forKey: fileId)
    }
}
