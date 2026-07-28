# Task 087: Web Security & IAM — OAuth 2.0 / PKCE Security Flow Validator

You are an IAM and API security engineer building an **OAuth 2.0 Authorization Code with PKCE (Proof Key for Code Exchange) Flow Verifier**.

## OAuth 2.0 / PKCE Verification Protocol

Given an OAuth authorization code exchange request (`/tests/oauth_request.json`):

1. **PKCE `code_challenge` S256 Validation**:
   - `code_challenge` sent during authorization:
     $$\text{Challenge} = \text{Base64URL\_NoPadding}(\text{SHA256}(\text{code\_verifier}))$$
   - Compare calculated challenge with stored `expected_code_challenge`.
2. **Redirect URI Exact Match**:
   - `redirect_uri` in token exchange MUST match registered `registered_redirect_uri` character-by-character.
3. **Authorization Code Single-Use / Expiration**:
   - `code_age_sec` MUST be $\le$ `max_code_lifetime_sec` (e.g. 60s).
   - `code_already_used` MUST be `false`.

## Input Schema (`/tests/oauth_request.json`)

```json
{
  "code_verifier": "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
  "expected_code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
  "redirect_uri": "https://client.app/oauth/callback",
  "registered_redirect_uri": "https://client.app/oauth/callback",
  "code_age_sec": 12,
  "max_code_lifetime_sec": 60,
  "code_already_used": false
}
```

## Objective

Write a Python 3 script `solution.py` with the class `OAuthPKCEValidator`:
```python
class OAuthPKCEValidator:
    def validate_token_request(self, filepath: str) -> dict:
        # filepath: path to oauth_request.json
        # returns: dict {"valid": bool, "error": "NONE" / "PKCE_MISMATCH" / "INVALID_REDIRECT_URI" / "CODE_EXPIRED" / "CODE_REPLAY"}
        pass
```

Save the script as `/src/solution.py`. When run directly (`cd /src && python3
solution.py`), it must read `/tests/oauth_request.json` and write the result to
`/src/oauth_result.json`.

## Constraints
- **Python Standard Library Only** (`hashlib`, `base64`, `json`, `os`, `sys`).
- Dynamic relative path resolution MUST be used for output.
