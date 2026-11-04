// GET /download → the newest Dict disk image. Every release attaches a copy
// named Dict.dmg (scripts/publish.sh), and GitHub serves the newest release's
// copy at this fixed address.
export const LATEST_DMG = "https://github.com/mattbirchler/Dict-releases/releases/latest/download/Dict.dmg";

export function GET() {
  return Response.redirect(LATEST_DMG, 302);
}
