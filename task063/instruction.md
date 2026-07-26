# Custom X.509 Certificate Chain Validator

## Objective

Implement a custom X.509 certificate chain validator that parses DER-encoded X.509 certificates **from scratch** and validates certificate chains.

**You may NOT use any of the following libraries:** `cryptography`, `pyOpenSSL`, `asn1crypto`, `pyasn1`, or any other ASN.1/crypto library. Only Python standard library modules are allowed (including `hashlib` for computing hashes).

## Requirements

Create a file `/src/solution.py` that implements the following class:

```python
class X509Validator:
    def validate_chain(self, cert_chain_path: str, timestamp: int) -> dict:
        """
        Validate a certificate chain.

        Args:
            cert_chain_path: Path to a file with concatenated DER certificates (length-prefixed)
            timestamp: Unix timestamp to check validity against

        Returns:
            dict with keys:
                'valid': bool - whether the entire chain is valid
                'subject': str - subject of the leaf certificate
                'issuer': str - issuer of the leaf certificate
                'chain_length': int - number of certificates in the chain
                'errors': list - list of error strings (empty if valid)
        """
        pass
```

## Implementation Details

Your implementation must:

1. **Parse ASN.1 DER encoding (Tag-Length-Value)** recursively, handling:
   - Short form and long form length encoding
   - Universal tags: SEQUENCE (0x30), SET (0x31), INTEGER (0x02), BIT STRING (0x03), OCTET STRING (0x04), NULL (0x05), OID (0x06), BOOLEAN (0x01), PrintableString (0x13), UTCTime (0x17), GeneralizedTime (0x18)
   - Context-specific constructed tags: `[0]` EXPLICIT (0xA0), `[3]` EXPLICIT (0xA3)

2. **Extract certificate fields**: version, serial number, issuer, subject, validity period (notBefore/notAfter), RSA public key (n, e), signature bytes

3. **Verify RSA signatures** using raw modular exponentiation: `pow(signature_int, e, n)`

4. **Verify PKCS#1 v1.5 signature padding**: `0x00 0x01 [0xFF padding] 0x00 [DigestInfo]`

5. **Validate the chain**: root CA → intermediate CA → leaf certificate (verify each cert's signature against the next cert's public key, and verify root is self-signed)

6. **Check validity periods** against the given reference timestamp

7. **Check Basic Constraints** extension: CA certificates must have `CA:TRUE`

## Chain File Format

Each chain file contains concatenated length-prefixed DER certificates:
```
[4 bytes big-endian: length of cert 1][cert 1 DER bytes]
[4 bytes big-endian: length of cert 2][cert 2 DER bytes]
[4 bytes big-endian: length of cert 3][cert 3 DER bytes]
```

Chain order: `[leaf, intermediate, root]`

## Error Types

Return these error strings in the `errors` list as applicable:
- `"certificate_expired"` — a certificate's validity period doesn't contain the timestamp
- `"signature_invalid"` — RSA signature verification failed for any cert in the chain
- `"basic_constraints_violation"` — a CA certificate doesn't have BasicConstraints with CA:TRUE

## Test Data

Chain files are located at `/data/chains/`:
- `chain_valid.der` — Valid 3-cert chain (root CA → intermediate CA → leaf)
- `chain_expired.der` — Chain with an expired leaf certificate
- `chain_wrong_issuer.der` — Chain where intermediate was signed by a different key than the root's
- `chain_bad_sig.der` — Chain with a corrupted leaf signature

**Reference timestamp:** `1735689600` (January 1, 2025, 00:00:00 UTC)

## Output

Your solution must validate **all four** chain files and write results as JSON to `/src/results.txt`:

```json
{
    "chain_valid.der": {"valid": true, "subject": "...", "issuer": "...", "chain_length": 3, "errors": []},
    "chain_expired.der": {"valid": false, "subject": "...", "issuer": "...", "chain_length": 3, "errors": ["certificate_expired"]},
    "chain_wrong_issuer.der": {"valid": false, "subject": "...", "issuer": "...", "chain_length": 3, "errors": ["signature_invalid"]},
    "chain_bad_sig.der": {"valid": false, "subject": "...", "issuer": "...", "chain_length": 3, "errors": ["signature_invalid"]}
}
```

## Hints

- The signature covers the **raw DER bytes** of the TBSCertificate element (the first child of the Certificate SEQUENCE, including its own tag and length bytes)
- RSA signature verification: compute `pow(sig_int, e, n)`, convert result to `key_size` bytes (big-endian), verify PKCS#1 v1.5 padding
- DigestInfo for SHA-256: `SEQUENCE { SEQUENCE { OID(2.16.840.1.101.3.4.2.1), NULL }, OCTET STRING { 32-byte-hash } }`
- OID encoding: first byte = `40*component[0] + component[1]`, remaining components use base-128 with high-bit continuation
- BIT STRING values have an "unused bits" count as their first byte (usually 0x00 for aligned data)
- X.509 extensions are wrapped in `[3] EXPLICIT` → `SEQUENCE of Extension` → each `Extension = SEQUENCE { OID, optional BOOLEAN critical, OCTET STRING value }`
