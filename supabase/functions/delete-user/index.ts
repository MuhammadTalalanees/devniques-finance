// Supabase Edge Function: delete-user
// Deletes a user from Supabase Auth AND public.profiles.
// Only callable by admins (verified via JWT + is_admin() check).
// Deploy via Supabase Dashboard > Edge Functions.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Caller identity from their JWT (anon key client).
    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user: caller },
    } = await userClient.auth.getUser();
    if (!caller) {
      return json({ error: "Unauthorized" }, 401);
    }

    // Admin check via is_admin() using the caller's JWT.
    const { data: isAdmin, error: adminErr } = await userClient.rpc(
      "is_admin",
    );
    if (adminErr || isAdmin !== true) {
      return json({ error: "Admin only" }, 403);
    }

    const { user_id } = await req.json();
    if (!user_id || typeof user_id !== "string") {
      return json({ error: "user_id required" }, 400);
    }
    if (user_id === caller.id) {
      return json({ error: "Cannot delete yourself" }, 400);
    }

    // Service-role client for admin operations.
    const admin = createClient(supabaseUrl, serviceKey);

    // 1) Delete from Auth (this is what "already exists" came from).
    const { error: authErr } = await admin.auth.admin.deleteUser(user_id);
    if (authErr) {
      // If auth user already gone, continue to clean the profile.
      console.log("auth delete note:", authErr.message);
    }

    // 2) Delete profile row.
    const { error: profErr } = await admin
      .from("profiles")
      .delete()
      .eq("id", user_id);
    if (profErr) throw profErr;

    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
