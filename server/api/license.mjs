// GET /api/license?session_id=cs_… → { key, activate, email }
// Called by the thanks page that Stripe sends buyers to.
import { privateKeyFromSeed } from "../lib/license.mjs";
import { CheckoutError, fetchStripeSession, licenseForSession } from "../lib/checkout.mjs";

export async function GET(request) {
  const sessionId = new URL(request.url).searchParams.get("session_id") ?? "";
  if (!/^cs_(test|live)_[A-Za-z0-9]+$/.test(sessionId)) {
    return Response.json({ error: "This link is missing its purchase id." }, { status: 400 });
  }
  if (!process.env.STRIPE_SECRET_KEY || !process.env.DICT_LICENSE_PRIVATE_KEY) {
    return Response.json({ error: "The store isn't open yet." }, { status: 503 });
  }
  try {
    const session = await fetchStripeSession(sessionId, process.env.STRIPE_SECRET_KEY);
    const license = licenseForSession(session, {
      paymentLink: process.env.DICT_PAYMENT_LINK_ID,
      privateKey: privateKeyFromSeed(process.env.DICT_LICENSE_PRIVATE_KEY),
    });
    return Response.json(license, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    const status = error instanceof CheckoutError ? error.status : 500;
    if (status === 500) console.error(error);
    const message = error instanceof CheckoutError ? error.message : "Something went wrong making your key.";
    return Response.json({ error: message }, { status });
  }
}
