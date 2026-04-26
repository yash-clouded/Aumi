import Foundation
import CryptoKit

/// X25519 key exchange + HKDF-SHA256 key derivation for Mac-side pairing.
class PairingManager {
    static let shared = PairingManager()

    private let info = "aumi-v1-session-key".data(using: .utf8)!

    // Ephemeral X25519 keypair — generated once per pairing session
    private let localPrivateKey = Curve25519.KeyAgreement.PrivateKey()

    var localPublicKeyBase64: String {
        localPrivateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    var localDeviceId: String {
        Host.current().localizedName ?? UUID().uuidString
    }

    /// Returns the pairing QR deep-link payload for display on the Mac.
    /// Android scans this to initiate pairing.
    func pairingQRContent(localIp: String, port: Int) -> String {
        "aumi://pair?id=\(localDeviceId)&pubkey=\(localPublicKeyBase64)&ip=\(localIp)&port=\(port)"
    }

    /// Called when Android sends its public key back after scanning the QR.
    /// Derives the shared AES-256 key and stores it in Keychain.
    func completePairing(androidPublicKeyBase64: String, androidDeviceId: String) throws -> SymmetricKey {
        guard let keyData = Data(base64Encoded: androidPublicKeyBase64) else {
            throw PairingError.invalidPublicKey
        }
        let androidPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: keyData)
        let sharedSecret = try localPrivateKey.sharedSecretFromKeyAgreement(with: androidPublicKey)

        // HKDF-SHA256: sharedSecret → 32-byte AES key
        let sessionKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: info,
            outputByteCount: 32
        )

        // Persist to Keychain
        KeychainStore.saveSessionKey(sessionKey.withUnsafeBytes { Data($0) })
        KeychainStore.savePeerId(androidDeviceId)

        return sessionKey
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
