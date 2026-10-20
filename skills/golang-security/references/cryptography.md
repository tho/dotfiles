# Cryptographic contracts

Use reviewed primitives and protocols with explicit key ownership and failure behavior. Security depends on their composition, input validation, and lifecycle as well as the algorithm name.

- Use `crypto/rand` for keys, unpredictable tokens, salts, and random nonces. Handle errors for APIs that return them on the supported Go version.
- Use authenticated encryption, such as AES-GCM or ChaCha20-Poly1305. Preserve nonce and format/version metadata needed for decryption; authenticate associated metadata when its alteration would change interpretation. Reject truncated or unauthenticated ciphertext without returning plaintext.
- For GCM, ensure nonce uniqueness per key. Random 96-bit nonces have a per-key message budget; respect the construction's limits, including the standard library's limit of at most 2^32 messages per key for random GCM nonces, aggregated across instances. Rotate before that budget is exhausted. Counters need coordinated uniqueness across replicas and restarts; an independent process counter is not sufficient.
- Derive operational key lifetimes from the remaining per-key message budget divided by the aggregate encryption rate across all replicas sharing that key. Keep units in the expression and verify numerical conversions with an available calculator or code tool. Without one, retain the unit-bearing expression instead of an unchecked conversion. Enforce the message budget across restarts and rate changes; a time estimate alone is not a usage limit.
- On Go 1.24+, `cipher.NewGCMWithRandomNonce` manages random nonces for AES and includes them in ciphertext. For older versions, manage the nonce explicitly with `crypto/rand`. Do not mix formats unknowingly.
- Envelope encryption separates data keys from their wrapping key. Retain key identifiers and authenticated metadata needed to unwrap historical data. Rewrapping data keys supports routine wrapping-key rotation; a compromised data key requires a different remediation plan than routine rewrapping.

## Passwords and comparisons

Use Argon2id with unique salts and stored, versioned cost parameters, or an appropriate established password hashing scheme. Bound decoded parameters before verification so hostile stored values cannot request unbounded memory or CPU. Tune costs to service capacity and bound concurrent verification work.

Go bcrypt rejects passwords over 72 bytes. Preserve an explicit long-password policy; use an appropriate scheme such as Argon2id when long passwords are required rather than silently truncating or inventing an undocumented prehash format. Fast SHA-256 alone is not password storage.

Use `hmac.Equal` for MAC verification and the password library's verifier where available. `subtle.ConstantTimeCompare` returns immediately on unequal lengths; it does not hide secret lengths. Fixed, public signature lengths can be checked explicitly. Argon2 produces a derived key, so an application still needs a constant-time comparison against the stored derived key. Streaming every byte through a MAC is valid; buffering the full message is not required.

## Signed messages and replay

A valid MAC proves integrity and authenticity under the key, not freshness or uniqueness. For incoming webhooks or commands, assess freshness and repeat-delivery semantics separately from signature verification, even when reviewing a streaming implementation. Verify the protocol's exact signed representation, including any timestamp or identifier relied on for freshness or deduplication; unauthenticated metadata cannot provide that guarantee.

Bound input before processing and authenticate it before consequential effects. Use the protocol's freshness window and atomic duplicate detection or durable idempotency as appropriate to its delivery contract. Legitimate retries must not repeat a payment or other effect. An integrity-only stored artifact may intentionally accept old content and repeated verification; do not invent expiration or replay rejection for that contract.

## Algorithm interpretation

Avoid broken algorithms for new security designs, but tie findings to the property required. A non-security checksum is different from password hashing. Hash collision attacks are not automatically HMAC forgeries. RSA PKCS#1 v1.5 encryption padding concerns do not establish a padding-oracle attack on RS256 signatures.

Use modern key sizes and project cryptographic policy, typically RSA of at least 2048 bits or suitable modern curves.
