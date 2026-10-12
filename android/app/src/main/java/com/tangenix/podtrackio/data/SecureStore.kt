package com.tangenix.podtrackio.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecureStore(context: Context) {
    private val preferences = context.getSharedPreferences("podtrackio_secure", Context.MODE_PRIVATE)
    private val alias = "podtrackio.local.secrets.v1"

    fun put(key: String, value: String?) {
        if (value == null) {
            preferences.edit().remove(key).apply()
            return
        }
        preferences.edit().putString(key, encrypt(value)).apply()
    }

    fun get(key: String): String? = preferences.getString(key, null)?.let { stored ->
        runCatching { decrypt(stored) }.getOrElse {
            preferences.edit().remove(key).apply()
            null
        }
    }

    fun remove(vararg keys: String) {
        preferences.edit().also { editor -> keys.forEach(editor::remove) }.apply()
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val body = Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        return "$iv:$body"
    }

    private fun decrypt(value: String): String {
        val parts = value.split(':', limit = 2)
        require(parts.size == 2) { "Unreadable encrypted preference" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey(),
            GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)),
        )
        return cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)).toString(Charsets.UTF_8)
    }

    companion object {
        const val ACCESS_TOKEN = "supabase_access_token"
        const val REFRESH_TOKEN = "supabase_refresh_token"
        const val GROQ_KEY = "groq_api_key"
        const val TRANSCRIPT_API_KEY = "transcript_api_key"
    }
}
