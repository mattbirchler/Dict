# Selling Dict

Dict is sold through a Stripe Payment Link. The app works for 14 days,
then dictation stops until a license key is entered. Keys are checked on
the Mac; Dict never contacts a server about them.

## How a sale works

1. Buy Dict (in the app, the menu, or the website) opens
   `https://dict-store.vercel.app/buy`, which redirects to the Payment Link.
2. After paying, Stripe sends the buyer to
   `https://dict-store.vercel.app/thanks?session_id={CHECKOUT_SESSION_ID}`.
3. That page calls `/api/license`. The function reads the checkout from
   Stripe, refuses it unless it's paid and came from Dict's Payment Link,
   and signs a key. The key is made from the checkout itself, so reloading
   the page gives the same key.
4. The page shows the key and an **Activate in Dict** button, a
   `dictapp://activate?key=…` link. Dict checks the signature and unlocks.
   (`dict://` belongs to Apple's Dictionary.)

## Keys

`DICT1-<payload>.<signature>`: base64url JSON (`email`, `purchase`,
`issued`, `product`, `v`) and its Ed25519 signature. Format and signing:
`server/lib/license.mjs`. Checking: `Dict-app/License.swift`. Tests on both
sides use the same test key, so a format change breaks one of them.

- **Signing key.** Made once with `scripts/license-keygen.sh`. The private
  half is in the login keychain (account `dict-license`) and in Vercel as
  `DICT_LICENSE_PRIVATE_KEY`; the public half is `License.publicKey`. Back
  the private half up with the Sparkle key. Losing it means no new keys
  without shipping a new public key; leaking it means anyone can make keys.
- **Keys by hand** (press, gifts, lost keys):
  `scripts/license-issue.sh someone@example.com`. To give a buyer back the
  exact key from checkout, pass their Checkout session id and purchase
  date: `scripts/license-issue.sh them@example.com cs_live_… 2026-11-20`.
- **Refunds.** A key can't be revoked; refunding is on trust. If that ever
  matters, a list of revoked purchase ids could ride along in the appcast.

## Store setup (Vercel project `dict-store`)

The site is `server/`: static pages in `public/`, functions in `api/`.
Deploy with `cd server && vercel deploy --prod`. Tests: `cd server && npm test`.

Environment variables (Production):

| Name | What |
| --- | --- |
| `DICT_LICENSE_PRIVATE_KEY` | Signing key seed, from the keychain |
| `STRIPE_SECRET_KEY` | A restricted key with read access to Checkout Sessions is enough |
| `DICT_PAYMENT_LINK_ID` | `plink_…` of Dict's Payment Link; checkouts from any other link are refused |
| `DICT_PAYMENT_LINK_URL` | `https://buy.stripe.com/…`, where `/buy` redirects |

In Stripe, set the Payment Link's confirmation page to "Don't show
confirmation page" and redirect to
`https://dict-store.vercel.app/thanks?session_id={CHECKOUT_SESSION_ID}`.
