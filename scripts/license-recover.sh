#!/bin/zsh
# Gives a buyer back the exact key they got at checkout, found by the email
# they paid with. Reads their purchases from Stripe and signs them again
# with the key in the keychain (scripts/license-keygen.sh). Keys are made
# from the checkout itself, so the result matches their original key.
#
#   scripts/license-recover.sh someone@example.com
#   scripts/license-recover.sh --setup     # once: save the Stripe details
#
# --setup saves a Stripe key (the store's restricted key with read access
# to Checkout Sessions is enough) and the plink_… id of Dict's Payment Link
# to the login keychain. STRIPE_SECRET_KEY and DICT_PAYMENT_LINK_ID in the
# environment win over the keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

ACCOUNT=dict-stripe
KEY_SERVICE="Dict Stripe key"
LINK_SERVICE="Dict payment link id"

if [[ "${1:-}" == "--setup" ]]; then
    echo "Paste the Stripe key (rk_live_… or sk_live_…) when asked."
    security add-generic-password -U -a "$ACCOUNT" -s "$KEY_SERVICE" -w
    echo "Now the Payment Link id (plink_…)."
    security add-generic-password -U -a "$ACCOUNT" -s "$LINK_SERVICE" -w
    echo "Saved. Recover keys with: scripts/license-recover.sh someone@example.com"
    exit 0
fi

EMAIL=${1:-}
[[ -n "$EMAIL" ]] || { echo "Usage: scripts/license-recover.sh email   (or --setup)" >&2; exit 1; }

missing() { echo "$1 Run scripts/license-recover.sh --setup first." >&2; exit 1; }
STRIPE_KEY=${STRIPE_SECRET_KEY:-$(security find-generic-password -a "$ACCOUNT" -s "$KEY_SERVICE" -w 2>/dev/null)} \
    || missing "No Stripe key in the keychain."
PAYMENT_LINK=${DICT_PAYMENT_LINK_ID:-$(security find-generic-password -a "$ACCOUNT" -s "$LINK_SERVICE" -w 2>/dev/null)} \
    || missing "No Payment Link id in the keychain."
SEED=$(security find-generic-password -a dict-license -s "Dict license signing key" -w) \
    || { echo "No license signing key in the keychain. Run scripts/license-keygen.sh first." >&2; exit 1; }

DICT_EMAIL="$EMAIL" DICT_SEED="$SEED" DICT_STRIPE_KEY="$STRIPE_KEY" DICT_LINK="$PAYMENT_LINK" node --input-type=module -e '
import { privateKeyFromSeed } from "./server/lib/license.mjs";
import { findStripeSessions, licenseForSession } from "./server/lib/checkout.mjs";

const email = process.env.DICT_EMAIL;
const privateKey = privateKeyFromSeed(process.env.DICT_SEED);
const paymentLink = process.env.DICT_LINK;
try {
  const sessions = await findStripeSessions(email, { secretKey: process.env.DICT_STRIPE_KEY, paymentLink });
  const licenses = [];
  for (const session of sessions) {
    try {
      const license = licenseForSession(session, { paymentLink, privateKey });
      licenses.push({ ...license, issued: new Date(session.created * 1000).toISOString().slice(0, 10) });
    } catch { /* not paid, so no key */ }
  }
  if (licenses.length === 0) {
    console.error(`No paid Dict purchases for ${email}.`);
    console.error("Stripe matches the address exactly as typed at checkout. Search the Stripe dashboard");
    console.error("for their name, then use scripts/license-issue.sh with the cs_live_… id and date.");
    process.exit(1);
  }
  licenses.forEach(({ key, activate, issued }, i) => {
    console.log(licenses.length > 1 ? `Purchase ${i + 1} of ${licenses.length}, ${issued}:` : `Purchased ${issued}:`);
    console.log(key);
    console.log();
    console.log("One-click activation link:");
    console.log(activate);
    if (i < licenses.length - 1) console.log();
  });
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
'
