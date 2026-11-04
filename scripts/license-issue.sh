#!/bin/zsh
# Makes a Dict license key by hand, for press copies, gifts, or someone who
# lost theirs. Signs with the key in the keychain (scripts/license-keygen.sh).
#
#   scripts/license-issue.sh someone@example.com [purchase] [YYYY-MM-DD]
#
# purchase defaults to "manual". To give a buyer back the exact key they got
# at checkout, pass their Checkout session id (cs_live_…, in the Stripe
# dashboard under the payment's details) and the purchase date.
set -euo pipefail
cd "$(dirname "$0")/.."

EMAIL=${1:-}
[[ -n "$EMAIL" ]] || { echo "Usage: scripts/license-issue.sh email [purchase] [YYYY-MM-DD]" >&2; exit 1; }
PURCHASE=${2:-manual}
ISSUED=${3:-$(date -u +%Y-%m-%d)}

SEED=$(security find-generic-password -a dict-license -s "Dict license signing key" -w) \
    || { echo "No license signing key in the keychain. Run scripts/license-keygen.sh first." >&2; exit 1; }

DICT_SEED="$SEED" node --input-type=module -e '
import { privateKeyFromSeed, issueLicense, activationURL } from "./server/lib/license.mjs";
const [email, purchase, issued] = process.argv.slice(1);
const key = issueLicense({ email, purchase, issued }, privateKeyFromSeed(process.env.DICT_SEED));
console.log(key);
console.log();
console.log("One-click activation link:");
console.log(activationURL(key));
' "$EMAIL" "$PURCHASE" "$ISSUED"
