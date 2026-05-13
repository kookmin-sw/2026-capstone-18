package com.littlesignals.app.capture

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface BlobCipher {
    fun encrypt(plaintext: ByteArray): ByteArray
    fun decrypt(ciphertext: ByteArray): ByteArray
}

class AesGcmBlobCipher(
    private val key: SecretKey,
    private val random: SecureRandom = SecureRandom(),
) : BlobCipher {
    override fun encrypt(plaintext: ByteArray): ByteArray {
        val nonce = ByteArray(NONCE_BYTES).also { random.nextBytes(it) }
        val cipher = Cipher.getInstance(TRANSFORM).apply {
            init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
        }
        val body = cipher.doFinal(plaintext)
        return ByteArray(nonce.size + body.size).also {
            System.arraycopy(nonce, 0, it, 0, nonce.size)
            System.arraycopy(body, 0, it, nonce.size, body.size)
        }
    }

    override fun decrypt(ciphertext: ByteArray): ByteArray {
        require(ciphertext.size >= NONCE_BYTES + TAG_BITS / 8) { "ciphertext too short" }
        val nonce = ciphertext.copyOfRange(0, NONCE_BYTES)
        val body = ciphertext.copyOfRange(NONCE_BYTES, ciphertext.size)
        val cipher = Cipher.getInstance(TRANSFORM).apply {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
        }
        return cipher.doFinal(body)
    }

    companion object {
        const val NONCE_BYTES = 12
        const val TAG_BITS = 128
        private const val TRANSFORM = "AES/GCM/NoPadding"
    }
}
