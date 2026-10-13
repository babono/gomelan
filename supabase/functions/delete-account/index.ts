// delete-account
//
// Deletes the calling player's account and everything filed under it, after
// revoking Sign in with Apple — App Store guideline 5.1.1(v) requires both an
// in-app deletion and, for Apple sign-in, revoking the user's Apple tokens.
//
// Called by the app with the player's own session (the gateway verifies the
// JWT) and a fresh Apple `authorization_code` from re-authenticating, which is
// the only way to obtain a token Apple will accept for revocation: the app
// never keeps the refresh token from sign-in.
//
// Secrets (Edge Functions → Secrets):
//   APPLE_TEAM_ID       10-character Team ID
//   APPLE_KEY_ID        Key ID of the Sign in with Apple key
//   APPLE_CLIENT_ID     the app's bundle ID, e.g. me.babono.kotek
//   APPLE_PRIVATE_KEY   contents of AuthKey_<KEY_ID>.p8, BEGIN/END lines included
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the platform.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Who is asking. The body is never trusted for this: the user id comes
  // from the verified session token alone.
  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "not signed in" }, 401);
  const { data: { user }, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !user) return json({ error: "not signed in" }, 401);

  const { authorization_code: code } = await req.json().catch(() => ({}));

  // Revoke first, while the account still exists to retry against. A failure
  // here does not stop the deletion: being unable to reach Apple must not
  // leave someone unable to delete their data.
  let revoked = false;
  if (typeof code === "string" && code.length > 0) {
    try {
      await revokeApple(code);
      revoked = true;
    } catch (e) {
      console.error("apple revoke failed", e);
    }
  }

  // Children before parents, so this works whether or not the foreign keys
  // cascade — the schema predates the migrations folder and is not recorded.
  const uid = user.id;
  // Checked, not assumed: a lookup that failed quietly would read as "owns
  // nothing" and skip the child rows, leaving them behind.
  const instruments = await admin.from("instruments").select("id").eq("user_id", uid);
  const kotekan = await admin.from("kotekan").select("id").eq("user_id", uid);
  const lookupError = instruments.error ?? kotekan.error;
  if (lookupError) {
    console.error("row lookup failed", lookupError);
    return json({ error: "could not delete data" }, 500);
  }
  const instrumentIds = (instruments.data ?? []).map((r) => r.id);
  const kotekanIds = (kotekan.data ?? []).map((r) => r.id);

  const steps = [
    admin.from("practice_session").delete().eq("user_id", uid),
    kotekanIds.length && admin.from("kotekan_hits").delete().in("kotekan_id", kotekanIds),
    admin.from("kotekan").delete().eq("user_id", uid),
    instrumentIds.length && admin.from("instrument_keys").delete().in("instrument_id", instrumentIds),
    admin.from("instruments").delete().eq("user_id", uid),
    admin.from("controllers").delete().eq("user_id", uid),
  ];
  for (const step of steps) {
    if (!step) continue;
    const { error } = await step;
    if (error) {
      console.error("row delete failed", error);
      return json({ error: "could not delete data" }, 500);
    }
  }

  // Gangsa photos: everything in the user's folder. Storage cannot be
  // emptied by deleting rows, only through its own API.
  const photos = admin.storage.from("instrument-photos");
  const { data: files, error: listError } = await photos.list(uid, { limit: 1000 });
  if (listError) {
    console.error("photo list failed", listError);
    return json({ error: "could not delete data" }, 500);
  }
  if (files && files.length) {
    const { error: removeError } = await photos.remove(files.map((f) => `${uid}/${f.name}`));
    if (removeError) {
      console.error("photo delete failed", removeError);
      return json({ error: "could not delete data" }, 500);
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) {
    console.error("user delete failed", deleteError);
    return json({ error: "could not delete account" }, 500);
  }

  return json({ deleted: true, revoked });
});

/// Exchange the one-time authorization code for a refresh token, then revoke
/// it — which ends the app's access to the Apple ID entirely, as if the
/// player had pressed "Stop Using Apple ID" in Settings.
async function revokeApple(code: string) {
  const clientId = Deno.env.get("APPLE_CLIENT_ID")!;
  const clientSecret = await appleClientSecret(clientId);

  const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      code,
      grant_type: "authorization_code",
    }),
  });
  if (!tokenRes.ok) throw new Error(`token ${tokenRes.status}: ${await tokenRes.text()}`);
  const { refresh_token: refreshToken } = await tokenRes.json();

  const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      token: refreshToken,
      token_type_hint: "refresh_token",
    }),
  });
  if (!revokeRes.ok) throw new Error(`revoke ${revokeRes.status}: ${await revokeRes.text()}`);
}

/// Apple's "client secret" is a short-lived ES256 JWT signed with the .p8 key.
async function appleClientSecret(clientId: string) {
  // A key pasted into a single-line secret field can arrive with literal
  // "\n" in place of line breaks, which PKCS8 parsing rejects.
  const pem = Deno.env.get("APPLE_PRIVATE_KEY")!.replace(/\\n/g, "\n");
  const key = await importPKCS8(pem, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: Deno.env.get("APPLE_KEY_ID")! })
    .setIssuer(Deno.env.get("APPLE_TEAM_ID")!)
    .setSubject(clientId)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);
}
