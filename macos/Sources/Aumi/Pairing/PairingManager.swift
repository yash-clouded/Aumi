import Foundation
import CryptoKit

/// X25519 key exchange + HKDF-SHA256 key derivation for Mac-side pairing.
class PairingManager {
    static let shared = PairingManager()

    private let info = "aumi-v1-session-key".data(using: .utf8)!

    private var currentPSK: SymmetricKey?
    private var currentPSKBase64: String?

    /// Generates a fresh PSK for a new QR code display.
    func prepareNewPairing() -> String {
        let key = SymmetricKey(size: .bits256)
        self.currentPSK = key
        let b64 = key.withUnsafeBytes { Data($0) }.base64EncodedString()
        self.currentPSKBase64 = b64
        
        // Save immediately as the "Expected" key
        KeychainStore.saveSessionKey(key.withUnsafeBytes { Data($0) })
        ConnectionManager.shared.refreshSessionKey()
        
        return b64
    }

    /// Called by the UI when the QR is successfully scanned (verified by phone's arrival).
    func finalizePairing(peerId: String) {
        guard let key = currentPSK else { return }
        KeychainStore.saveSessionKey(key.withUnsafeBytes { Data($0) })
        KeychainStore.savePeerId(peerId)
        ConnectionManager.shared.refreshSessionKey()
    }

    /// Loads a previously established session key from Keychain.
    func loadSessionKey() -> SymmetricKey? {
        guard let data = KeychainStore.loadSessionKey() else { return nil }
        return SymmetricKey(data: data)
    }

    enum PairingError: Error {
        case invalidPublicKey
        case keyDerivationFailed
    }
}
