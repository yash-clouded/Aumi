package com.aumi.app.crypto

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

object AESCipher {
    private const val ALGORITHM = "AES/GCM/NoPadding"
    private const val IV_LENGTH = 12  // 96-bit IV for GCM
    private const val TAG_LENGTH = 128 // 128-bit auth tag

    /**
     * Encrypts [plaintext] with AES-256-GCM.
     * Returns IV (12B) + ciphertext + auth tag (16B) as a single ByteArray.
     */
    fun encrypt(key: ByteArray, plaintext: ByteArray): ByteArray {
        val iv = ByteArray(IV_LENGTH).also {
            java.security.SecureRandom().nextBytes(it)
        }
        val cipher = Cipher.getInstance(ALGORITHM)
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_LENGTH, iv))
        val ciphertext = cipher.doFinal(plaintext)
        return iv + ciphertext  // prepend IV for transport
    }

    /**
     * Decrypts a payload produced by [encrypt].
     * Expects IV (12B) + ciphertext + tag.
     */
    fun decrypt(key: ByteArray, payload: ByteArray): ByteArray {
        require(payload.size > IV_LENGTH) { "Payload too short to contain IV" }
        val iv = payload.sliceArray(0 until IV_LENGTH)
        val ciphertext = payload.sliceArray(IV_LENGTH until payload.size)
        val cipher = Cipher.getInstance(ALGORITHM)
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_LENGTH, iv))
        return cipher.doFinal(ciphertext)
    }
}
