// GET /buy → Dict's Stripe Payment Link. The app's Buy button points here,
// so the price or link can change without shipping a new version.
export function GET() {
  const url = process.env.DICT_PAYMENT_LINK_URL;
  if (!url) return new Response("The store isn't open yet.", { status: 503 });
  return Response.redirect(url, 302);
}
