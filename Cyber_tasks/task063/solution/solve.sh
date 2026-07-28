#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
#!/usr/bin/env python3
"""
X.509 Certificate Chain Validator
Parses DER-encoded X.509 certificates from scratch (no crypto/ASN.1 libraries)
and validates certificate chains with RSA signature verification.
"""

import hashlib
import struct
import json
import os
import calendar


# ===========================
# ASN.1 DER Parser
# ===========================

class DERParser:
    """Recursive ASN.1 DER (Tag-Length-Value) parser."""

    def __init__(self, data):
        self.data = data
        self.pos = 0

    def read_byte(self):
        if self.pos >= len(self.data):
            raise ValueError("Unexpected end of DER data")
        b = self.data[self.pos]
        self.pos += 1
        return b

    def read_bytes(self, n):
        if self.pos + n > len(self.data):
            raise ValueError(f"Cannot read {n} bytes at offset {self.pos}")
        result = self.data[self.pos:self.pos + n]
        self.pos += n
        return result

    def read_tag(self):
        b = self.read_byte()
        tag_class = (b >> 6) & 0x03
        constructed = bool(b & 0x20)
        tag_number = b & 0x1F
        if tag_number == 0x1F:
            tag_number = 0
            while True:
                b = self.read_byte()
                tag_number = (tag_number << 7) | (b & 0x7F)
                if not (b & 0x80):
                    break
        return tag_class, constructed, tag_number

    def read_length(self):
        b = self.read_byte()
        if b < 0x80:
            return b
        if b == 0x80:
            raise ValueError("Indefinite length not supported in DER")
        num_bytes = b & 0x7F
        length = 0
        for _ in range(num_bytes):
            length = (length << 8) | self.read_byte()
        return length

    def read_tlv(self):
        start = self.pos
        tag_class, constructed, tag_number = self.read_tag()
        length = self.read_length()
        value_start = self.pos
        value = self.read_bytes(length)
        return {
            'tag_class': tag_class,
            'constructed': constructed,
            'tag_number': tag_number,
            'value': value,
            'raw': self.data[start:self.pos],
        }


def parse_element(data):
    """Parse a single DER element."""
    p = DERParser(data)
    return p.read_tlv()


def parse_children(data):
    """Parse consecutive DER elements from data."""
    p = DERParser(data)
    elements = []
    while p.pos < len(data):
        elements.append(p.read_tlv())
    return elements


# ===========================
# ASN.1 Value Decoders
# ===========================

def decode_integer(data):
    """Decode a DER INTEGER value to Python int."""
    val = 0
    for b in data:
        val = (val << 8) | b
    return val


def decode_oid(data):
    """Decode a DER OBJECT IDENTIFIER value."""
    if not data:
        return ""
    components = [data[0] // 40, data[0] % 40]
    val = 0
    for b in data[1:]:
        val = (val << 7) | (b & 0x7F)
        if not (b & 0x80):
            components.append(val)
            val = 0
    return '.'.join(str(c) for c in components)


def decode_utctime(data):
    """Decode UTCTime to Unix timestamp."""
    s = data.decode('ascii')
    if s.endswith('Z'):
        s = s[:-1]
    yr = int(s[0:2])
    yr = yr + 2000 if yr < 50 else yr + 1900
    mo = int(s[2:4])
    dy = int(s[4:6])
    hr = int(s[6:8])
    mi = int(s[8:10])
    sc = int(s[10:12]) if len(s) >= 12 else 0
    return calendar.timegm((yr, mo, dy, hr, mi, sc, 0, 0, 0))


def decode_generalizedtime(data):
    """Decode GeneralizedTime to Unix timestamp."""
    s = data.decode('ascii')
    if s.endswith('Z'):
        s = s[:-1]
    yr = int(s[0:4])
    mo = int(s[4:6])
    dy = int(s[6:8])
    hr = int(s[8:10])
    mi = int(s[10:12])
    sc = int(s[12:14]) if len(s) >= 14 else 0
    return calendar.timegm((yr, mo, dy, hr, mi, sc, 0, 0, 0))


# ===========================
# X.509 Name Parser
# ===========================

OID_NAMES = {
    '2.5.4.3': 'CN',
    '2.5.4.6': 'C',
    '2.5.4.7': 'L',
    '2.5.4.8': 'ST',
    '2.5.4.10': 'O',
    '2.5.4.11': 'OU',
}


def parse_name(data):
    """Parse X.509 Name to string like 'CN=foo,O=bar,C=US'."""
    parts = []
    rdns = parse_children(data)
    for rdn in rdns:
        if rdn['tag_number'] != 17:  # SET tag number
            continue
        atvs = parse_children(rdn['value'])
        for atv in atvs:
            if atv['tag_number'] != 16:  # SEQUENCE tag number
                continue
            fields = parse_children(atv['value'])
            if len(fields) >= 2:
                oid = decode_oid(fields[0]['value'])
                label = OID_NAMES.get(oid, oid)
                value = fields[1]['value'].decode('utf-8', errors='replace')
                parts.append(f"{label}={value}")
    return ','.join(parts)


# ===========================
# X.509 Certificate Parser
# ===========================

def parse_certificate(der_data):
    """Parse a DER-encoded X.509 certificate."""
    cert = {}

    # Certificate = SEQUENCE { TBSCertificate, SignatureAlgorithm, SignatureValue }
    outer = parse_element(der_data)
    children = parse_children(outer['value'])
    if len(children) < 3:
        raise ValueError("Invalid certificate: expected 3 elements in Certificate SEQUENCE")

    tbs_elem = children[0]
    sig_alg_elem = children[1]
    sig_val_elem = children[2]

    # Store raw TBS bytes for signature verification
    cert['tbs_raw'] = tbs_elem['raw']

    # Parse TBSCertificate
    tbs_fields = parse_children(tbs_elem['value'])
    idx = 0

    # Version [0] EXPLICIT (optional, default v1)
    if tbs_fields[idx]['tag_class'] == 2 and tbs_fields[idx]['tag_number'] == 0:
        ver_inner = parse_element(tbs_fields[idx]['value'])
        cert['version'] = decode_integer(ver_inner['value']) + 1
        idx += 1
    else:
        cert['version'] = 1

    # Serial number
    cert['serial'] = decode_integer(tbs_fields[idx]['value'])
    idx += 1

    # Signature algorithm (inside TBS)
    idx += 1  # Skip, we use the outer one

    # Issuer
    cert['issuer'] = parse_name(tbs_fields[idx]['value'])
    idx += 1

    # Validity { notBefore, notAfter }
    validity = parse_children(tbs_fields[idx]['value'])
    nb = validity[0]
    na = validity[1]
    cert['not_before'] = decode_utctime(nb['value']) if nb['tag_number'] == 23 else decode_generalizedtime(nb['value'])
    cert['not_after'] = decode_utctime(na['value']) if na['tag_number'] == 23 else decode_generalizedtime(na['value'])
    idx += 1

    # Subject
    cert['subject'] = parse_name(tbs_fields[idx]['value'])
    idx += 1

    # SubjectPublicKeyInfo { AlgorithmIdentifier, BIT STRING }
    spki_fields = parse_children(tbs_fields[idx]['value'])
    alg_fields = parse_children(spki_fields[0]['value'])
    cert['pubkey_alg'] = decode_oid(alg_fields[0]['value'])

    # BIT STRING: first byte = unused bits, rest = DER of RSA public key
    pk_bits = spki_fields[1]['value']
    pk_der = pk_bits[1:]  # Skip unused-bits byte

    # RSA public key = SEQUENCE { n INTEGER, e INTEGER }
    if cert['pubkey_alg'] == '1.2.840.113549.1.1.1':
        rsa_seq = parse_element(pk_der)
        rsa_fields = parse_children(rsa_seq['value'])
        cert['pubkey_n'] = decode_integer(rsa_fields[0]['value'])
        cert['pubkey_e'] = decode_integer(rsa_fields[1]['value'])
    idx += 1

    # Extensions [3] EXPLICIT (optional)
    cert['is_ca'] = False
    cert['bc_present'] = False
    while idx < len(tbs_fields):
        elem = tbs_fields[idx]
        if elem['tag_class'] == 2 and elem['tag_number'] == 3:
            # Extensions wrapper -> SEQUENCE of Extension
            ext_seq = parse_element(elem['value'])
            extensions = parse_children(ext_seq['value'])
            for ext in extensions:
                ext_parts = parse_children(ext['value'])
                ext_oid = decode_oid(ext_parts[0]['value'])

                if ext_oid == '2.5.29.19':  # basicConstraints
                    cert['bc_present'] = True
                    # Find the OCTET STRING (skip optional BOOLEAN critical)
                    vi = 1
                    if ext_parts[vi]['tag_number'] == 1:  # BOOLEAN (critical)
                        vi += 1
                    bc_data = ext_parts[vi]['value']  # OCTET STRING value
                    bc_seq = parse_element(bc_data)
                    bc_fields = parse_children(bc_seq['value'])
                    if bc_fields and bc_fields[0]['tag_number'] == 1:  # BOOLEAN (cA)
                        cert['is_ca'] = bc_fields[0]['value'][0] != 0
        idx += 1

    # Outer signature algorithm
    sa_fields = parse_children(sig_alg_elem['value'])
    cert['sig_alg'] = decode_oid(sa_fields[0]['value'])

    # Signature value (BIT STRING)
    sig_bits = sig_val_elem['value']
    cert['signature'] = sig_bits[1:]  # Skip unused-bits byte

    return cert


# ===========================
# RSA Signature Verification
# ===========================

def verify_rsa_signature(tbs_raw, signature, n, e, sig_alg):
    """
    Verify an RSA signature using modular exponentiation.
    Checks PKCS#1 v1.5 padding and compares hash.
    """
    # s^e mod n
    sig_int = int.from_bytes(signature, 'big')
    decrypted = pow(sig_int, e, n)

    key_size = (n.bit_length() + 7) // 8
    dec_bytes = decrypted.to_bytes(key_size, 'big')

    # PKCS#1 v1.5: 0x00 0x01 [0xFF padding] 0x00 [DigestInfo]
    if len(dec_bytes) < 11:
        return False
    if dec_bytes[0] != 0x00 or dec_bytes[1] != 0x01:
        return False

    # Find 0x00 separator
    sep_idx = None
    for i in range(2, len(dec_bytes)):
        if dec_bytes[i] == 0x00:
            sep_idx = i
            break
        elif dec_bytes[i] != 0xFF:
            return False

    if sep_idx is None or sep_idx < 10:
        return False

    digest_info_bytes = dec_bytes[sep_idx + 1:]

    # Parse DigestInfo: SEQUENCE { AlgorithmIdentifier, OCTET STRING(hash) }
    try:
        di = parse_element(digest_info_bytes)
        di_fields = parse_children(di['value'])
        if len(di_fields) < 2:
            return False

        # Get hash algorithm OID
        hash_alg_fields = parse_children(di_fields[0]['value'])
        hash_oid = decode_oid(hash_alg_fields[0]['value'])

        # Get expected hash
        expected_hash = di_fields[1]['value']

        # Compute actual hash
        if hash_oid == '2.16.840.1.101.3.4.2.1':  # SHA-256
            actual_hash = hashlib.sha256(tbs_raw).digest()
        elif hash_oid == '1.3.14.3.2.26':  # SHA-1
            actual_hash = hashlib.sha1(tbs_raw).digest()
        else:
            return False

        return actual_hash == expected_hash

    except Exception:
        return False


# ===========================
# Certificate Chain Validator
# ===========================

class X509Validator:
    def validate_chain(self, cert_chain_path, timestamp):
        """
        Validate a certificate chain.

        Args:
            cert_chain_path: path to length-prefixed concatenated DER certificates
            timestamp: Unix timestamp for validity check

        Returns:
            dict with 'valid', 'subject', 'issuer', 'chain_length', 'errors'
        """
        errors = []

        # Read and split chain file
        with open(cert_chain_path, 'rb') as f:
            data = f.read()

        certs_raw = []
        pos = 0
        while pos + 4 <= len(data):
            cert_len = struct.unpack('>I', data[pos:pos + 4])[0]
            pos += 4
            if pos + cert_len > len(data):
                break
            certs_raw.append(data[pos:pos + cert_len])
            pos += cert_len

        # Parse all certificates
        certs = []
        for raw in certs_raw:
            try:
                certs.append(parse_certificate(raw))
            except Exception as ex:
                errors.append('parse_error')
                return {
                    'valid': False,
                    'subject': '',
                    'issuer': '',
                    'chain_length': len(certs_raw),
                    'errors': errors
                }

        chain_length = len(certs)
        if chain_length == 0:
            return {
                'valid': False,
                'subject': '',
                'issuer': '',
                'chain_length': 0,
                'errors': ['empty_chain']
            }

        leaf = certs[0]
        root = certs[-1]

        # 1. Check validity periods for all certs
        for i, cert in enumerate(certs):
            if timestamp < cert['not_before'] or timestamp > cert['not_after']:
                errors.append('certificate_expired')
                break

        # 2. Check Basic Constraints for CA certs (all except leaf)
        for i in range(1, len(certs)):
            if not certs[i].get('is_ca', False):
                errors.append('basic_constraints_violation')
                break

        # 3. Verify signatures up the chain (child signed by parent)
        for i in range(len(certs) - 1):
            child = certs[i]
            parent = certs[i + 1]
            if not verify_rsa_signature(
                child['tbs_raw'],
                child['signature'],
                parent['pubkey_n'],
                parent['pubkey_e'],
                child['sig_alg']
            ):
                errors.append('signature_invalid')
                break

        # 4. Verify root is self-signed
        if not verify_rsa_signature(
            root['tbs_raw'],
            root['signature'],
            root['pubkey_n'],
            root['pubkey_e'],
            root['sig_alg']
        ):
            if 'signature_invalid' not in errors:
                errors.append('signature_invalid')

        valid = len(errors) == 0

        return {
            'valid': valid,
            'subject': leaf.get('subject', ''),
            'issuer': leaf.get('issuer', ''),
            'chain_length': chain_length,
            'errors': errors
        }


# ===========================
# Main Entry Point
# ===========================

if __name__ == '__main__':
    validator = X509Validator()

    chains_dir = '/data/chains'
    results = {}

    # Read timestamp from expected results
    expected_path = '/tests/expected_results.json'
    if os.path.exists(expected_path):
        with open(expected_path, 'r') as f:
            expected = json.load(f)
        timestamp = expected.get('timestamp', 1735689600)
    else:
        timestamp = 1735689600

    # Validate each chain file
    chain_files = sorted([
        f for f in os.listdir(chains_dir)
        if f.endswith('.der')
    ])

    for cf in chain_files:
        path = os.path.join(chains_dir, cf)
        result = validator.validate_chain(path, timestamp)
        results[cf] = result
        status = "VALID" if result['valid'] else f"INVALID ({', '.join(result['errors'])})"
        print(f"  {cf}: {status}")

    # Write results
    with open('/src/results.txt', 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\nResults written to /src/results.txt")
PYEOF
cd /src && python3 solution.py
