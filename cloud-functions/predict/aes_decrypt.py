"""
AES-128-CBC decryption for incoming ESP32 sensor batches.

The ESP32 encrypts a protobuf-serialized SensorBatch using AES-128-CBC
with PKCS7 padding. This module decrypts it.
"""

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend


def decrypt_aes128_cbc(key: bytes, iv: bytes, ciphertext: bytes) -> bytes:
    """Decrypt AES-128-CBC with PKCS7 padding.

    Args:
        key:        16-byte AES key
        iv:         16-byte initialization vector
        ciphertext: encrypted data (multiple of 16 bytes)

    Returns:
        Decrypted plaintext bytes

    Raises:
        ValueError: if key/iv length is wrong or padding is invalid
    """
    if len(key) != 16:
        raise ValueError(f"AES-128 key must be 16 bytes, got {len(key)}")
    if len(iv) != 16:
        raise ValueError(f"IV must be 16 bytes, got {len(iv)}")
    if len(ciphertext) == 0 or len(ciphertext) % 16 != 0:
        raise ValueError(f"Ciphertext length must be multiple of 16, got {len(ciphertext)}")

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    decryptor = cipher.decryptor()
    padded_plaintext = decryptor.update(ciphertext) + decryptor.finalize()

    # Remove PKCS7 padding
    unpadder = padding.PKCS7(128).unpadder()
    plaintext = unpadder.update(padded_plaintext) + unpadder.finalize()

    return plaintext
