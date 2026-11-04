// Turns a finished Stripe Checkout session into a Dict license key.
import { issueLicense, activationURL } from "./license.mjs";

export class CheckoutError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/** Reads a Checkout session from Stripe's API. No SDK needed for one call. */
export async function fetchStripeSession(sessionId, secretKey, fetchImpl = fetch) {
  const response = await fetchImpl(
    "https://api.stripe.com/v1/checkout/sessions/" + encodeURIComponent(sessionId),
    { headers: { Authorization: "Bearer " + secretKey } },
  );
  if (response.status === 404) throw new CheckoutError(404, "That purchase wasn't found.");
  if (!response.ok) throw new CheckoutError(502, "Stripe didn't answer. Reload the page in a minute.");
  return response.json();
}

/**
 * session: a Stripe Checkout session object.
 * paymentLink: the plink_… id of Dict's Payment Link. Sessions from any
 * other product on the same Stripe account are refused.
 */
export function licenseForSession(session, { paymentLink, privateKey }) {
  if (!paymentLink) throw new CheckoutError(500, "The store isn't set up yet (no payment link).");
  if (session.payment_link !== paymentLink) {
    throw new CheckoutError(403, "That purchase isn't for Dict.");
  }
  const paid = session.status === "complete" &&
    (session.payment_status === "paid" || session.payment_status === "no_payment_required");
  if (!paid) throw new CheckoutError(402, "That purchase hasn't been paid yet. Reload the page in a minute.");

  const email = session.customer_details?.email ?? session.customer_email;
  if (!email) throw new CheckoutError(500, "That purchase has no email address.");
  // The checkout's own date, so reloading the page gives the same key.
  const issued = new Date(session.created * 1000).toISOString().slice(0, 10);
  const key = issueLicense({ email, purchase: session.id, issued }, privateKey);
  return { key, activate: activationURL(key), email };
}
