#!/usr/bin/env python3
"""
Self-contained X.509 certificate chain generator.
No external dependencies - uses only Python stdlib.
Generates 4 test chains: valid, expired, wrong_issuer, bad_sig.
Output: /data/chains/*.der
"""

import os
import struct
import hashlib
import random

random.seed(42)

# ===========================
# RSA Key Generation
# ===========================

SMALL_PRIMES = [
    2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67,
    71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137, 139, 149,
    151, 157, 163, 167, 173, 179, 181, 191, 193, 197, 199, 211, 223, 227, 229,
    233, 239, 241, 251, 257, 263, 269, 271, 277, 281, 283, 293, 307, 311, 313,
    317, 331, 337, 347, 349, 353, 359, 367, 373, 379, 383, 389, 397, 401, 409,
    419, 421, 431, 433, 439, 443, 449, 457, 461, 463, 467, 479, 487, 491, 499,
    503, 509, 521, 523, 541, 547, 557, 563, 569, 571, 577, 587, 593, 599, 601,
    607, 613, 617, 619, 631, 641, 643, 647, 653, 659, 661, 673, 677, 683, 691,
    701, 709, 719, 727, 733, 739, 743, 751, 757, 761, 769, 773, 787, 797, 809,
    811, 821, 823, 827, 829, 839, 853, 857, 859, 863, 877, 881, 883, 887, 907,
    911, 919, 929, 937, 941, 947, 953, 967, 971, 977, 983, 991, 997
]


def is_probable_prime(n, k=15):
    """Miller-Rabin primality test."""
    if n < 2:
        return False
    if n < 4:
        return True
    if n % 2 == 0:
        return False
    for p in SMALL_PRIMES:
        if n == p:
            return True
        if n % p == 0:
            return False
    # Write n-1 as 2^r * d
    r, d = 0, n - 1
    while d % 2 == 0:
        r += 1
        d //= 2
    for _ in range(k):
        a = random.randrange(2, n - 1)
        x = pow(a, d, n)
        if x == 1 or x == n - 1:
            continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def generate_prime(bits):
    """Generate a random prime of the given bit length."""
    while True:
        n = random.getrandbits(bits)
        n |= (1 << (bits - 1)) | 1  # Ensure correct bit length and odd
        if is_probable_prime(n):
            return n


def extended_gcd(a, b):
    if a == 0:
        return b, 0, 1
    gcd, x1, y1 = extended_gcd(b % a, a)
    x = y1 - (b // a) * x1
    y = x1
    return gcd, x, y


def mod_inverse(e, phi):
    gcd, x, _ = extended_gcd(e % phi, phi)
    if gcd != 1:
        raise ValueError("Modular inverse doesn't exist")
    return x % phi


def generate_rsa_keypair(bits=1024):
    """Generate an RSA key pair."""
    half = bits // 2
    p = generate_prime(half)
    q = generate_prime(half)
    while p == q:
        q = generate_prime(half)
    n = p * q
    phi = (p - 1) * (q - 1)
    e = 65537
    d = mod_inverse(e, phi)
    return {'n': n, 'e': e, 'd': d, 'p': p, 'q': q}


# ===========================
# DER Encoding Primitives
# ===========================

def der_length(length):
    """Encode a DER length field."""
    if length < 0x80:
        return bytes([length])
    else:
        lb = length.to_bytes((length.bit_length() + 7) // 8, 'big')
        return bytes([0x80 | len(lb)]) + lb


def der_tlv(tag, value):
    """Encode a DER Tag-Length-Value."""
    if isinstance(value, int):
        value = bytes([value])
    return bytes([tag]) + der_length(len(value)) + value


def der_sequence(elements):
    return der_tlv(0x30, b''.join(elements))


def der_set(elements):
    return der_tlv(0x31, b''.join(elements))


def der_integer(value):
    if value == 0:
        return der_tlv(0x02, b'\x00')
    byte_len = (value.bit_length() + 8) // 8  # Extra byte for sign bit
    vb = value.to_bytes(byte_len, 'big')
    # Strip unnecessary leading zero bytes (keep one if high bit set)
    while len(vb) > 1 and vb[0] == 0 and vb[1] < 0x80:
        vb = vb[1:]
    return der_tlv(0x02, vb)


def der_oid(oid_str):
    parts = [int(x) for x in oid_str.split('.')]
    encoded = bytes([40 * parts[0] + parts[1]])
    for part in parts[2:]:
        if part < 0x80:
            encoded += bytes([part])
        else:
            chunks = []
            val = part
            while val > 0:
                chunks.append(val & 0x7F)
                val >>= 7
            chunks.reverse()
            for i in range(len(chunks) - 1):
                encoded += bytes([chunks[i] | 0x80])
            encoded += bytes([chunks[-1]])
    return der_tlv(0x06, encoded)


def der_boolean(value):
    return der_tlv(0x01, b'\xFF' if value else b'\x00')


def der_null():
    return der_tlv(0x05, b'')


def der_bit_string(data):
    return der_tlv(0x03, b'\x00' + data)


def der_octet_string(data):
    return der_tlv(0x04, data)


def der_printable_string(s):
    return der_tlv(0x13, s.encode('ascii'))


def der_utctime(year, month, day, hour, minute, second):
    if year >= 2000:
        ys = f"{year - 2000:02d}"
    else:
        ys = f"{year - 1900:02d}"
    ts = f"{ys}{month:02d}{day:02d}{hour:02d}{minute:02d}{second:02d}Z"
    return der_tlv(0x17, ts.encode('ascii'))


def der_explicit(tag_number, content):
    """Encode as context-specific constructed [tag_number] EXPLICIT."""
    return der_tlv(0xA0 | tag_number, content)


# ===========================
# X.509 OIDs
# ===========================

OID_RSA = '1.2.840.113549.1.1.1'
OID_SHA256_RSA = '1.2.840.113549.1.1.11'
OID_SHA256 = '2.16.840.1.101.3.4.2.1'
OID_CN = '2.5.4.3'
OID_O = '2.5.4.10'
OID_C = '2.5.4.6'
OID_BC = '2.5.29.19'


# ===========================
# X.509 Certificate Builders
# ===========================

def build_alg_id(oid):
    return der_sequence([der_oid(oid), der_null()])


def build_name(cn, org, country):
    rdns = []
    for oid, val in [(OID_CN, cn), (OID_O, org), (OID_C, country)]:
        atv = der_sequence([der_oid(oid), der_printable_string(val)])
        rdns.append(der_set([atv]))
    return der_sequence(rdns)


def build_validity(nb, na):
    return der_sequence([
        der_utctime(*nb),
        der_utctime(*na)
    ])


def build_spki(n, e):
    rsa_key = der_sequence([der_integer(n), der_integer(e)])
    return der_sequence([build_alg_id(OID_RSA), der_bit_string(rsa_key)])


def build_extensions(is_ca, path_length=None):
    bc_content = []
    if is_ca:
        bc_content.append(der_boolean(True))
        if path_length is not None:
            bc_content.append(der_integer(path_length))
    bc_val = der_sequence(bc_content)
    ext = der_sequence([
        der_oid(OID_BC),
        der_boolean(True),  # critical
        der_octet_string(bc_val)
    ])
    return der_explicit(3, der_sequence([ext]))


def build_tbs(serial, issuer, subject, nb, na, pub_n, pub_e, is_ca, path_len=None):
    elems = [
        der_explicit(0, der_integer(2)),  # version v3
        der_integer(serial),
        build_alg_id(OID_SHA256_RSA),
        issuer,
        build_validity(nb, na),
        subject,
        build_spki(pub_n, pub_e),
        build_extensions(is_ca, path_len)
    ]
    return der_sequence(elems)


def sign_tbs(tbs_der, priv_key):
    """PKCS#1 v1.5 sign with SHA-256."""
    h = hashlib.sha256(tbs_der).digest()
    digest_info = der_sequence([
        der_sequence([der_oid(OID_SHA256), der_null()]),
        der_octet_string(h)
    ])
    n = priv_key['n']
    key_size = (n.bit_length() + 7) // 8
    pad_len = key_size - 3 - len(digest_info)
    if pad_len < 8:
        raise ValueError("Key too small")
    padded = b'\x00\x01' + b'\xFF' * pad_len + b'\x00' + digest_info
    m = int.from_bytes(padded, 'big')
    s = pow(m, priv_key['d'], priv_key['n'])
    return s.to_bytes(key_size, 'big')


def build_cert(tbs_der, signature):
    return der_sequence([
        tbs_der,
        build_alg_id(OID_SHA256_RSA),
        der_bit_string(signature)
    ])


def build_chain_file(cert_ders):
    """Build length-prefixed chain file."""
    data = bytearray()
    for cd in cert_ders:
        data += struct.pack('>I', len(cd))
        data += cd
    return bytes(data)


# ===========================
# Chain Generation
# ===========================

def gen_valid_chain():
    """Generate a valid 3-cert chain."""
    print("  Generating valid chain keys...")
    rk = generate_rsa_keypair(1024)
    ik = generate_rsa_keypair(1024)
    lk = generate_rsa_keypair(1024)

    rn = build_name("Test Root CA", "Test Org", "US")
    iname = build_name("Test Intermediate CA", "Test Org", "US")
    ln = build_name("test.example.com", "Test Org", "US")

    # Root (self-signed)
    rt = build_tbs(1, rn, rn, (2024,1,1,0,0,0), (2030,12,31,23,59,59),
                   rk['n'], rk['e'], True)
    rc = build_cert(rt, sign_tbs(rt, rk))

    # Intermediate (signed by root)
    it = build_tbs(2, rn, iname, (2024,1,1,0,0,0), (2029,12,31,23,59,59),
                   ik['n'], ik['e'], True, 0)
    ic = build_cert(it, sign_tbs(it, rk))

    # Leaf (signed by intermediate)
    lt = build_tbs(3, iname, ln, (2024,6,1,0,0,0), (2026,6,1,0,0,0),
                   lk['n'], lk['e'], False)
    lc = build_cert(lt, sign_tbs(lt, ik))

    return build_chain_file([lc, ic, rc])


def gen_expired_chain():
    """Generate a chain with an expired leaf certificate."""
    print("  Generating expired chain keys...")
    rk = generate_rsa_keypair(1024)
    ik = generate_rsa_keypair(1024)
    lk = generate_rsa_keypair(1024)

    rn = build_name("Expired Root CA", "Test Org", "US")
    iname = build_name("Expired Intermediate CA", "Test Org", "US")
    ln = build_name("expired.example.com", "Test Org", "US")

    rt = build_tbs(10, rn, rn, (2020,1,1,0,0,0), (2030,12,31,23,59,59),
                   rk['n'], rk['e'], True)
    rc = build_cert(rt, sign_tbs(rt, rk))

    it = build_tbs(11, rn, iname, (2020,1,1,0,0,0), (2030,12,31,23,59,59),
                   ik['n'], ik['e'], True, 0)
    ic = build_cert(it, sign_tbs(it, rk))

    # Leaf expired on 2022-01-01
    lt = build_tbs(12, iname, ln, (2020,1,1,0,0,0), (2022,1,1,0,0,0),
                   lk['n'], lk['e'], False)
    lc = build_cert(lt, sign_tbs(lt, ik))

    return build_chain_file([lc, ic, rc])


def gen_wrong_issuer_chain():
    """Generate a chain where intermediate is signed by wrong key."""
    print("  Generating wrong issuer chain keys...")
    rk = generate_rsa_keypair(1024)
    ik = generate_rsa_keypair(1024)
    wrong_k = generate_rsa_keypair(1024)  # Wrong signer
    lk = generate_rsa_keypair(1024)

    rn = build_name("WrongIssuer Root CA", "Test Org", "US")
    iname = build_name("WrongIssuer Intermediate CA", "Test Org", "US")
    ln = build_name("wrongissuer.example.com", "Test Org", "US")

    rt = build_tbs(20, rn, rn, (2024,1,1,0,0,0), (2030,12,31,23,59,59),
                   rk['n'], rk['e'], True)
    rc = build_cert(rt, sign_tbs(rt, rk))

    # Intermediate: issuer says root, but signed by wrong_k
    it = build_tbs(21, rn, iname, (2024,1,1,0,0,0), (2029,12,31,23,59,59),
                   ik['n'], ik['e'], True, 0)
    ic = build_cert(it, sign_tbs(it, wrong_k))  # Wrong signer!

    lt = build_tbs(22, iname, ln, (2024,6,1,0,0,0), (2026,6,1,0,0,0),
                   lk['n'], lk['e'], False)
    lc = build_cert(lt, sign_tbs(lt, ik))

    return build_chain_file([lc, ic, rc])


def gen_bad_sig_chain():
    """Generate a chain with corrupted leaf signature."""
    print("  Generating bad sig chain keys...")
    rk = generate_rsa_keypair(1024)
    ik = generate_rsa_keypair(1024)
    lk = generate_rsa_keypair(1024)

    rn = build_name("BadSig Root CA", "Test Org", "US")
    iname = build_name("BadSig Intermediate CA", "Test Org", "US")
    ln = build_name("badsig.example.com", "Test Org", "US")

    rt = build_tbs(30, rn, rn, (2024,1,1,0,0,0), (2030,12,31,23,59,59),
                   rk['n'], rk['e'], True)
    rc = build_cert(rt, sign_tbs(rt, rk))

    it = build_tbs(31, rn, iname, (2024,1,1,0,0,0), (2029,12,31,23,59,59),
                   ik['n'], ik['e'], True, 0)
    ic = build_cert(it, sign_tbs(it, rk))

    lt = build_tbs(32, iname, ln, (2024,6,1,0,0,0), (2026,6,1,0,0,0),
                   lk['n'], lk['e'], False)
    lc_bytes = bytearray(build_cert(lt, sign_tbs(lt, ik)))
    # Corrupt the last byte of the DER (in the signature)
    lc_bytes[-1] ^= 0x01
    lc = bytes(lc_bytes)

    return build_chain_file([lc, ic, rc])


def main():
    out_dir = '/data/chains'
    os.makedirs(out_dir, exist_ok=True)
    print("Generating X.509 test certificate chains...")

    chain = gen_valid_chain()
    with open(os.path.join(out_dir, 'chain_valid.der'), 'wb') as f:
        f.write(chain)
    print("  -> chain_valid.der written")

    chain = gen_expired_chain()
    with open(os.path.join(out_dir, 'chain_expired.der'), 'wb') as f:
        f.write(chain)
    print("  -> chain_expired.der written")

    chain = gen_wrong_issuer_chain()
    with open(os.path.join(out_dir, 'chain_wrong_issuer.der'), 'wb') as f:
        f.write(chain)
    print("  -> chain_wrong_issuer.der written")

    chain = gen_bad_sig_chain()
    with open(os.path.join(out_dir, 'chain_bad_sig.der'), 'wb') as f:
        f.write(chain)
    print("  -> chain_bad_sig.der written")

    print("All certificate chains generated successfully!")


if __name__ == '__main__':
    main()
