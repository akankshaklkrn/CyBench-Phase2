#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import hashlib
import base64
import os

class OAuthPKCEValidator:
    def validate_token_request(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        verifier = data['code_verifier']
        exp_challenge = data['expected_code_challenge']
        r_uri = data['redirect_uri']
        reg_uri = data['registered_redirect_uri']
        age = data['code_age_sec']
        max_lifetime = data['max_code_lifetime_sec']
        already_used = data['code_already_used']
        
        # 1. Code replay check
        if already_used:
            return {"valid": False, "error": "CODE_REPLAY"}
            
        # 2. Expiration check
        if age > max_lifetime:
            return {"valid": False, "error": "CODE_EXPIRED"}
            
        # 3. Redirect URI exact match
        if r_uri != reg_uri:
            return {"valid": False, "error": "INVALID_REDIRECT_URI"}
            
        # 4. PKCE S256 Challenge match
        digest = hashlib.sha256(verifier.encode('ascii')).digest()
        calc_challenge = base64.urlsafe_b64encode(digest).decode('ascii').rstrip('=')
        
        if calc_challenge != exp_challenge:
            return {"valid": False, "error": "PKCE_MISMATCH"}
            
        return {"valid": True, "error": "NONE"}

if __name__ == "__main__":
    fp = "/tests/oauth_request.json"
    if not os.path.exists(fp):
        fp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "oauth_request.json")
    validator = OAuthPKCEValidator()
    res = validator.validate_token_request(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/oauth_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
