package com.littlesignals.app.capture

import javax.crypto.KeyGenerator
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BlobCipherTest {
    private val key = SecretKeySpec(ByteArray(32) { it.toByte() }, "AES")

    @Test fun `round-trip recovers plaintext`() {
        val cipher = AesGcmBlobCipher(key)
        val plaintext = "biosignal-sample-data".toByteArray()
        val ciphertext = cipher.encrypt(plaintext)
        assertArrayEquals(plaintext, cipher.decrypt(ciphertext))
    }

    @Test fun `ciphertext is longer than plaintext by nonce plus tag`() {
        val cipher = AesGcmBlobCipher(key)
        val plaintext = ByteArray(100)
        val ciphertext = cipher.encrypt(plaintext)
        assertEquals(100 + 12 + 16, ciphertext.size)
    }

    @Test fun `two encryptions of same plaintext produce different ciphertext`() {
        val cipher = AesGcmBlobCipher(key)
        val plaintext = "same".toByteArray()
        val a = cipher.encrypt(plaintext)
        val b = cipher.encrypt(plaintext)
        assertNotEquals(a.toList(), b.toList())
    }

    @Test fun `tampering with ciphertext throws`() {
        val cipher = AesGcmBlobCipher(key)
        val ciphertext = cipher.encrypt("payload".toByteArray())
        ciphertext[ciphertext.size - 1] = (ciphertext[ciphertext.size - 1].toInt() xor 1).toByte()
        assertThrows(Exception::class.java) { cipher.decrypt(ciphertext) }
    }

    @Test fun `tampering with nonce throws`() {
        val cipher = AesGcmBlobCipher(key)
        val ciphertext = cipher.encrypt("payload".toByteArray())
        ciphertext[0] = (ciphertext[0].toInt() xor 1).toByte()
        assertThrows(Exception::class.java) { cipher.decrypt(ciphertext) }
    }

    @Test fun `wrong key cannot decrypt`() {
        val a = AesGcmBlobCipher(key)
        val ciphertext = a.encrypt("payload".toByteArray())
        val otherKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val b = AesGcmBlobCipher(otherKey)
        assertThrows(Exception::class.java) { b.decrypt(ciphertext) }
    }

    @Test fun `empty plaintext round-trips`() {
        val cipher = AesGcmBlobCipher(key)
        val ciphertext = cipher.encrypt(ByteArray(0))
        assertTrue(cipher.decrypt(ciphertext).isEmpty())
    }
}
