#!/bin/zsh
# Creates the Ed25519 key that signs Dict license keys. Run it once.
#
# The private key goes into the login keychain (account "dict-license"),
# where scripts/license-issue.sh and the Vercel setup read it. The public
# key is printed: it belongs in Dict-app/License.swift.
#
# Losing the private key means every key sold so far still works, but no
# new ones can be made without shipping a new public key. Back it up
# (a password manager is fine): security find-generic-password -a dict-license -w
set -euo pipefail

ACCOUNT=dict-license
SERVICE="Dict license signing key"

if security find-generic-password -a "$ACCOUNT" -s "$SERVICE" >/dev/null 2>&1; then
    echo "A license signing key already exists in the keychain. Its public key:" >&2
    security find-generic-password -a "$ACCOUNT" -s "$SERVICE" -w | node "$(dirname "$0")/../server/lib/public-key.mjs"
    exit 0
fi

PAIR=$(node -e '
const { generateKeyPairSync } = require("node:crypto");
const jwk = generateKeyPairSync("ed25519").privateKey.export({ format: "jwk" });
const b64 = (s) => Buffer.from(s, "base64url").toString("base64");
console.log(b64(jwk.d) + " " + b64(jwk.x));
')
PRIVATE=${PAIR% *}
PUBLIC=${PAIR#* }

security add-generic-password -a "$ACCOUNT" -s "$SERVICE" -w "$PRIVATE"
echo "Saved the private key to the keychain (account $ACCOUNT)."
echo "Public key for Dict-app/License.swift:"
echo "$PUBLIC"
