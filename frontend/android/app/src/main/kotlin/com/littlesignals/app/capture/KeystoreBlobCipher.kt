package com.littlesignals.app.capture

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * Loads (or lazily creates) a hardware-backed 256-bit AES master key in the
 * AndroidKeyStore under alias [ALIAS]. The key never leaves the Keystore;
 * `javax.crypto.Cipher` operations are proxied through it.
 *
 * Privacy invariant: the key is bound to this device install. Reinstalling
 * the app or resetting the device makes previously uploaded biosignal blobs
 * permanently unreadable — this is the deliberate property that backs the
 * "server cannot decrypt" claim in README §2.1.
 */
class KeystoreBlobCipher(
    private val delegate: BlobCipher = AesGcmBlobCipher(loadOrCreateKey()),
) : BlobCipher by delegate {
    companion object {
        const val ALIAS = "little_signals_biosignal_v1"
        private const val PROVIDER = "AndroidKeyStore"
        private const val KEY_SIZE_BITS = 256

        @Synchronized
        private fun loadOrCreateKey(): SecretKey {
            val ks = KeyStore.getInstance(PROVIDER).apply { load(null) }
            val existing = ks.getEntry(ALIAS, null)
            if (existing != null) {
                return (existing as? KeyStore.SecretKeyEntry)?.secretKey
                    ?: throw IllegalStateException(
                        "AndroidKeyStore alias '$ALIAS' is occupied by a non-SecretKey entry",
                    )
            }
            return generateKey(strongBox = true)
                ?: generateKey(strongBox = false)
                ?: error("AndroidKeyStore key generation failed for alias '$ALIAS'")
        }

        private fun generateKey(strongBox: Boolean): SecretKey? {
            val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
            val spec = KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(KEY_SIZE_BITS)
                .setRandomizedEncryptionRequired(true)
                .apply { if (strongBox) setIsStrongBoxBacked(true) }
                .build()
            return try {
                gen.init(spec)
                gen.generateKey()
            } catch (_: StrongBoxUnavailableException) {
                null
            }
        }
    }
}
