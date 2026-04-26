package com.aumi.app.pairing

import android.util.Base64
import com.aumi.app.crypto.AESCipher
import com.aumi.app.crypto.AumiKeyStore
import java.security.KeyPairGenerator
import java.security.interfaces.XECPublicKey
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Manages the X25519 key exchange and HKDF-SHA256 key derivation for pairing.
 *
 * Flow:
 *  Android (Scan QR) ──► reads Mac's public key from QR
 *                     ──► generates own ephemeral X25519 keypair
 *                     ──► performs ECDH → shared secret
 *                     ──► derives AES-256 key via HKDF-SHA256
 *                     ──► saves key to Keystore
 *                     ──► sends own public key to Mac over TCP
 */
object PairingManager {

    private const val ALGORITHM = "X25519"
    private const val HKDF_INFO = "aumi-v1-session-key"

    data class PairingPayload(
        val deviceId: String,
        val publicKeyBase64: String,
        val ip: String,
        val port: Int
    )

    // Ephemeral keypair — generated fresh each pairing attempt
    private var keyPairGenerator = KeyPairGenerator.getInstance(ALGORITHM, "AndroidKeyStore").apply {
        initialize(android.security.keystore.KeyGenParameterSpec.Builder(
            "aumi_ephemeral",
            android.security.keystore.KeyProperties.PURPOSE_AGREE_KEY
        ).build())
    }
    private val localKeyPair = keyPairGenerator.generateKeyPair()

    /**
     * Returns this device's public key as Base64 for embedding in the QR code.
     */
    fun getLocalPublicKeyBase64(): String {
        return Base64.encodeToString(localKeyPair.public.encoded, Base64.NO_WRAP)
    }

    /**
     * Called once QR is scanned. Derives the shared AES key from Mac's public key.
     * @param peerPublicKeyBase64 the Mac's X25519 public key from the QR code
     * @return the derived AES-256 key bytes (32 bytes)
     */
    fun deriveSessionKey(peerPublicKeyBase64: String): ByteArray {
        val peerKeyBytes = Base64.decode(peerPublicKeyBase64, Base64.NO_WRAP)

        // Reconstruct peer's public key
        val keyFactory = java.security.KeyFactory.getInstance(ALGORITHM, "AndroidKeyStore")
        val peerPublicKey = keyFactory.generatePublic(
            java.security.spec.X509EncodedKeySpec(peerKeyBytes)
        )

        // ECDH agreement → shared secret
        val keyAgreement = KeyAgreement.getInstance(ALGORITHM, "AndroidKeyStore")
        keyAgreement.init(localKeyPair.private)
        keyAgreement.doPhase(peerPublicKey, true)
        val sharedSecret = keyAgreement.generateSecret()

        // HKDF-SHA256 → 32-byte AES key
        return hkdfExpand(hkdfExtract(sharedSecret), HKDF_INFO.toByteArray(), 32)
    }

    /**
     * Saves the derived session key + peer ID to Keystore.
     */
    fun completePairing(sessionKey: ByteArray, peerId: String) {
        AumiKeyStore.saveSessionKey(sessionKey)
        AumiKeyStore.savePeerId(peerId)
    }

    // ── HKDF (RFC 5869) ──────────────────────────────────────────────────────

    private fun hkdfExtract(inputKeyMaterial: ByteArray, salt: ByteArray = ByteArray(32)): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(salt, "HmacSHA256"))
        return mac.doFinal(inputKeyMaterial)
    }

    private fun hkdfExpand(prk: ByteArray, info: ByteArray, length: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        val result = ByteArray(length)
        var previousBlock = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < length) {
            mac.update(previousBlock)
            mac.update(info)
            mac.update(counter.toByte())
            previousBlock = mac.doFinal()
            val copyLen = minOf(previousBlock.size, length - offset)
            previousBlock.copyInto(result, offset, 0, copyLen)
            offset += copyLen
            counter++
        }
        return result
    }
}
