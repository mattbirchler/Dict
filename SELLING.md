# Selling Dict

Dict is sold through a Stripe Payment Link. The app works for 14 days,
then dictation stops until a license key is entered. Keys are checked on
the Mac; Dict never contacts a server about them.

## How a sale works

1. Buy Dict (in the app, the menu, or the website) opens
   `https://dictapp.app/buy`, which redirects to the Payment Link.
2. After paying, Stripe sends the buyer to
   `https://dictapp.app/thanks?session_id={CHECKOUT_SESSION_ID}`.
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
  half is in the login keychain (account `dict-license`) and in Railway as
  `DICT_LICENSE_PRIVATE_KEY`; the public half is `License.publicKey`. Back
  the private half up with the Sparkle key. Losing it means no new keys
  without shipping a new public key; leaking it means anyone can make keys.
- **Keys by hand** (press, gifts, lost keys):
  `scripts/license-issue.sh someone@example.com`. To give a buyer back the
  exact key from checkout, pass their Checkout session id and purchase
  date: `scripts/license-issue.sh them@example.com cs_live_… 2026-11-20`.
- **Refunds.** A key can't be revoked; refunding is on trust. If that ever
  matters, a list of revoked purchase ids could ride along in the appcast.

## Store setup (Railway project `dict-store`, service `store`)

The store lives at `https://dictapp.app` (bought through Vercel, which
hosts its DNS). The root record there is an ALIAS to the Railway target
shown by `railway domain list`, plus a `_railway-verify` TXT record. The
Railway address `https://store-production-8e91.up.railway.app` still works
and older builds of Dict point there, so keep it.

The site is `server/`: a dependency-free Node server (`server.mjs`) that
serves the pages in `public/` and the two handlers in `api/`. Railway
runs it with `npm start` and gives it `PORT`. `/healthz` answers `ok`.

```bash
cd server
npm test                      # handler and server tests
railway up                    # deploy (the folder is linked to the service)
railway logs                  # see what it's doing
```

Set variables with `railway variable set NAME --stdin` so secrets never
land in shell history. The signing key, straight from the keychain:
`security find-generic-password -a dict-license -w | tr -d '\n' | railway variable set DICT_LICENSE_PRIVATE_KEY --stdin`.

Variables (production environment):

| Name | What |
| --- | --- |
| `DICT_LICENSE_PRIVATE_KEY` | Signing key seed, from the keychain |
| `STRIPE_SECRET_KEY` | A restricted key with read access to Checkout Sessions is enough |
| `DICT_PAYMENT_LINK_ID` | `plink_…` of Dict's Payment Link; checkouts from any other link are refused |
| `DICT_PAYMENT_LINK_URL` | `https://buy.stripe.com/…`, where `/buy` redirects |

In Stripe, set the Payment Link's confirmation page to "Don't show
confirmation page" and redirect to
`https://dictapp.app/thanks?session_id={CHECKOUT_SESSION_ID}`.
