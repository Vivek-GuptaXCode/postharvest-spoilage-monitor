"""
AES-128-CBC Pre-Shared Key for sensor data encryption.

HACKATHON NOTE: In production, retrieve from Google Cloud Secret Manager:
    from google.cloud import secretmanager
    client = secretmanager.SecretManagerServiceClient()
    key = client.access_secret_version(
        name="projects/postharvest-hack/secrets/aes-key/versions/latest"
    )

For the hackathon, we use a hardcoded PSK that matches the ESP32 firmware.
"""

import os

# 16 bytes = AES-128. Must match ESP32 firmware exactly.
# IoT team key: b'MySecretKey12345' → hex 4d795365637265744b65793132333435
AES_128_KEY = os.environ.get(
    "AES_128_KEY",
    b"MySecretKey12345"
)

# If env var is a hex string, convert it
if isinstance(AES_128_KEY, str):
    AES_128_KEY = bytes.fromhex(AES_128_KEY)

assert len(AES_128_KEY) == 16, f"AES key must be 16 bytes, got {len(AES_128_KEY)}"
