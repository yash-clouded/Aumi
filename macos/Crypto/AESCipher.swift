import Foundation
import CryptoKit

/// AES-256-GCM encryption/decryption using Apple's CryptoKit.
/// Wire format: [12-byte nonce][ciphertext+16-byte auth tag]
enum AESCipher {

    /// Encrypts plaintext with the given 32-byte symmetric key.
    /// Returns nonce (12B) + ciphertext + auth tag (16B).
    static func encrypt(key: SymmetricKey, plaintext: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        // CryptoKit's combined representation = nonce(12) + ciphertext + tag(16)
        guard let combined = sealedBox.combined else {
            throw AumiCryptoError.encryptionFailed
        }
        return combined
    }

    /// Decrypts a payload produced by `encrypt`.
    static func decrypt(key: SymmetricKey, payload: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: payload)
        return try AES.GCM.open(sealedBox, using: key)
    }
}

enum AumiCryptoError: Error {
    case encryptionFailed
    case decryptionFailed
    case invalidKeyLength
}
