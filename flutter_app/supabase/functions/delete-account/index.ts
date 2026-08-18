// Deletes the calling user's Supabase auth account and profile row.
// Called by the Flutter app's "Delete Account" action (Settings screen).
// Required for Apple App Store Guideline 5.1.1(v) — in-app account deletion.
import { createClient } from "jsr:@supabase/supabase-js@2";

const USER_SCOPED_BUCKETS = ["story-covers", "vocabulary-audio"];
const PAGE_SIZE = 100;

async function listUserFiles(
  bucket: ReturnType<ReturnType<typeof createClient>["storage"]["from"]>,
  prefix: string,
): Promise<string[]> {
  const files: string[] = [];
  let offset = 0;

  while (true) {
    const { data, error } = await bucket.list(prefix, {
      limit: PAGE_SIZE,
      offset,
    });
    if (error) throw new Error(`Storage list failed: ${error.message}`);
    if (!data || data.length === 0) break;

    for (const entry of data) {
      const path = `${prefix}/${entry.name}`;
      // Storage folders have no id; recurse so nested paths such as
      // <user-id>/v1/<cache-key>.pcm are removed too.
      if (entry.id) {
        files.push(path);
      } else {
        files.push(...await listUserFiles(bucket, path));
      }
    }

    if (data.length < PAGE_SIZE) break;
    offset += data.length;
  }

  return files;
}

async function deleteUserStorage(
  admin: ReturnType<typeof createClient>,
  userId: string,
) {
  for (const bucketName of USER_SCOPED_BUCKETS) {
    const bucket = admin.storage.from(bucketName);
    const paths = await listUserFiles(bucket, userId);
    for (let index = 0; index < paths.length; index += PAGE_SIZE) {
      const chunk = paths.slice(index, index + PAGE_SIZE);
      const { error } = await bucket.remove(chunk);
      if (error) {
        throw new Error(
          `Storage delete failed for ${bucketName}: ${error.message}`,
        );
      }
    }
  }
}

// Several early tables were created without ON DELETE CASCADE. Auth deletion
// therefore fails for a real learner who has generated content, even though
// the profile row itself can be deleted. Keep this list explicit and ordered:
// dependent rows first, then their parent rows, then auth.users last.
const USER_DATA_TABLES: Array<[string, string]> = [
  ["plan_task_state", "user_id"],
  ["learning_plan_state", "user_id"],
  ["adaptive_course_sessions", "user_id"],
  ["adaptive_course_plans", "user_id"],
  ["ai_session_state", "user_id"],
  ["daily_session_state", "user_id"],
  ["referral_redemptions", "redeemed_by_user_id"],
  ["subscription_invite_redemptions", "redeemed_by_user_id"],
  ["referral_codes", "owner_user_id"],
  ["generated_grammar_stories", "user_id"],
  ["generated_roleplays", "user_id"],
  ["generated_stories", "user_id"],
  ["generated_vocabulary_sets", "user_id"],
  ["generated_writing_tasks", "user_id"],
  ["vocabulary_audio_cache", "user_id"],
  ["chat_messages_state", "user_id"],
  ["notes_state", "user_id"],
  ["sessions_state", "user_id"],
  ["vocab_card_state", "user_id"],
  ["learner_competency_state", "user_id"],
  ["learner_events", "user_id"],
  ["credit_usage_state", "user_id"],
  ["lesson_progress_state", "user_id"],
  ["mistake_tag_state", "user_id"],
];

Deno.serve(async (req: Request) => {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Resolve the caller's own identity from their JWT — never trust a
  // user id passed in the request body, since that would let anyone
  // delete anyone else's account.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  if (callerError || !callerData.user) {
    return new Response(JSON.stringify({ error: "Invalid session" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }
  const userId = callerData.user.id;

  const admin = createClient(supabaseUrl, serviceRoleKey);

  try {
    // Supabase Auth refuses to delete an auth user who owns Storage objects.
    // Remove private learner-scoped files through Storage first, not by
    // deleting storage.objects rows directly (which would orphan blobs).
    await deleteUserStorage(admin, userId);

    // A referral code owned by this user can be referenced by redemptions
    // from other users. Remove those referencing rows before deleting the
    // owner's code, otherwise that old foreign key can block deletion.
    const { data: ownedCodes, error: referralLookupError } = await admin
      .from("referral_codes")
      .select("code")
      .eq("owner_user_id", userId);
    if (referralLookupError) {
      throw new Error(
        `Referral cleanup lookup failed: ${referralLookupError.message}`,
      );
    }
    const codes = (ownedCodes ?? [])
      .map((row) => row.code)
      .filter((code): code is string => typeof code === "string");
    if (codes.length > 0) {
      const { error } = await admin
        .from("referral_redemptions")
        .delete()
        .in("code", codes);
      if (error) {
        throw new Error(`Referral cleanup failed: ${error.message}`);
      }
    }

    for (const [table, column] of USER_DATA_TABLES) {
      const { error } = await admin.from(table).delete().eq(column, userId);
      if (error) {
        throw new Error(`Data cleanup failed for ${table}: ${error.message}`);
      }
    }

    const { error: profileError } = await admin
      .from("profiles")
      .delete()
      .eq("id", userId);
    if (profileError) {
      throw new Error(`Profile cleanup failed: ${profileError.message}`);
    }
  } catch (error) {
    return new Response(JSON.stringify({
      error: error instanceof Error ? error.message : String(error),
    }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    return new Response(JSON.stringify({ error: deleteError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
