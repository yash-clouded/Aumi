package com.aumi.app.crypto

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import android.util.Base64

/**
 * Persists the AES-256 symmetric session key using Android's EncryptedSharedPreferences,
 * which is backed by the Android Keystore hardware security module.
 */
object AumiKeyStore {
    private const val PREFS_FILE = "aumi_secure_prefs"
    private const val KEY_SESSION_KEY = "session_aes_key"
    private const val KEY_PEER_ID = "paired_peer_id"

    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        prefs = EncryptedSharedPreferences.create(
            context,
            PREFS_FILE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    fun saveSessionKey(key: ByteArray) {
        prefs.edit().putString(KEY_SESSION_KEY, Base64.encodeToString(key, Base64.NO_WRAP)).apply()
    }

    fun loadSessionKey(): ByteArray? {
        val encoded = prefs.getString(KEY_SESSION_KEY, null) ?: return null
        return Base64.decode(encoded, Base64.NO_WRAP)
    }

    fun savePeerId(peerId: String) {
        prefs.edit().putString(KEY_PEER_ID, peerId).apply()
    }

    fun loadPeerId(): String? = prefs.getString(KEY_PEER_ID, null)

    fun clearPairing() {
        prefs.edit().remove(KEY_SESSION_KEY).remove(KEY_PEER_ID).apply()
    }

    fun isPaired(): Boolean {
        if (!::prefs.isInitialized) return false
        return loadSessionKey() != null
    }
}
