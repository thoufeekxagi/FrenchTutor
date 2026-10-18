import { createClient } from "jsr:@supabase/supabase-js@2";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
const levels = new Set(["a1", "a2", "b1", "b2"]);

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers });
}

function key(name: string): string | undefined {
  const direct = Deno.env.get(name);
  if (direct) return direct;
  if (name === "SUPABASE_ANON_KEY") {
    const publishable = Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
    if (publishable) return publishable;
    try {
      const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
      if (typeof keys.default === "string") return keys.default;
    } catch (_) {
      // Use the clear configuration error below.
    }
  }
  if (name === "SUPABASE_SERVICE_ROLE_KEY") {
    return Deno.env.get("SUPABASE_SECRET_KEY");
  }
  return undefined;
}

function validDate(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return json({ error: "POST required" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const publicKey = key("SUPABASE_ANON_KEY");
  const serviceKey = key("SUPABASE_SERVICE_ROLE_KEY");
  const authHeader = request.headers.get("Authorization");
  if (!url || !publicKey || !serviceKey) {
    return json({ error: "Daily challenge service is not configured." }, 503);
  }
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: "Sign in to use daily challenges." }, 401);
  }

  try {
    const userClient = createClient(url, publicKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const token = authHeader.slice("Bearer ".length);
    const { data: userData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !userData.user) {
      return json({ error: "Sign in to use daily challenges." }, 401);
    }
    const userId = userData.user.id;
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const input = await request.json();
    const action = input.action;

    if (action === "today") {
      const level = String(input.level ?? "").toLowerCase();
      const localDate = input.local_date;
      if (!levels.has(level) || !validDate(localDate)) {
        return json({ error: "A valid level and local date are required." }, 400);
      }
      const requestedDate = new Date(`${localDate}T00:00:00.000Z`);
      if (Number.isNaN(requestedDate.valueOf()) ||
        requestedDate.toISOString().slice(0, 10) !== localDate) {
        return json({ error: "A real calendar date is required." }, 400);
      }
      const latestAllowedDate = new Date();
      latestAllowedDate.setUTCDate(latestAllowedDate.getUTCDate() + 1);
      if (requestedDate > new Date(`${latestAllowedDate.toISOString().slice(0, 10)}T00:00:00.000Z`)) {
        return json({ error: "The requested challenge date is too far ahead." }, 400);
      }
      const statuses = Deno.env.get("DAILY_CHALLENGE_INCLUDE_PREVIEW") === "true"
        ? ["published", "preview"]
        : ["published"];
      const { data: version, error: versionError } = await admin
        .from("daily_challenge_versions")
        .select(
          "id, challenge_key, revision, level_band, primary_skill, available_on, title, summary, minutes, step_labels, source_lesson_ids, content_json",
        )
        .eq("level_band", level)
        .eq("available_on", localDate)
        .in("status", statuses)
        .order("revision", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (versionError) {
        console.error("Daily challenge lookup failed", versionError.code);
        return json({ error: "Today's challenge is not available." }, 503);
      }
      if (!version) return json({ challenge: null, attempt: null });

      const { data: attempt, error: attemptError } = await admin
        .from("daily_challenge_attempts")
        .upsert({
          user_id: userId,
          challenge_version_id: version.id,
          learner_local_date: localDate,
          last_active_at: new Date().toISOString(),
        }, { onConflict: "user_id,challenge_version_id,learner_local_date" })
        .select("id, status, current_step")
        .single();
      if (attemptError) {
        console.error("Daily challenge attempt start failed", attemptError.code);
        return json({ error: "Could not save challenge progress." }, 503);
      }

      return json({
        challenge: {
          id: version.id,
          level: version.level_band,
          primary_skill: version.primary_skill,
          title: version.title,
          summary: version.summary,
          minutes: version.minutes,
          steps: version.step_labels,
          lesson: version.content_json.lesson,
        },
        attempt,
      });
    }

    const attemptId = String(input.attempt_id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(attemptId)) {
      return json({ error: "A valid attempt is required." }, 400);
    }
    const { data: attempt, error: attemptError } = await admin
      .from("daily_challenge_attempts")
      .select("id, user_id, challenge_version_id, learner_local_date, status, current_step, started_at")
      .eq("id", attemptId)
      .eq("user_id", userId)
      .maybeSingle();
    if (attemptError || !attempt) return json({ error: "Attempt not found." }, 404);
    if (attempt.status === "completed" && action !== "today") {
      return json({ error: "This challenge is already complete." }, 409);
    }

    if (action === "start") {
      const now = new Date().toISOString();
      const { error } = await admin
        .from("daily_challenge_attempts")
        .update({
          status: "started",
          started_at: attempt.started_at ?? now,
          last_active_at: now,
        })
        .eq("id", attemptId)
        .eq("user_id", userId);
      if (error) return json({ error: "Could not start this challenge." }, 503);
      return json({ ok: true });
    }
    if (attempt.status !== "started") {
      return json({ error: "Start the challenge before saving progress." }, 409);
    }

    const { data: version, error: versionError } = await admin
      .from("daily_challenge_versions")
      .select("content_json, answer_key_json")
      .eq("id", attempt.challenge_version_id)
      .maybeSingle();
    if (versionError || !version) return json({ error: "Challenge version not found." }, 404);
    const steps = version.content_json?.lesson?.steps;
    if (!Array.isArray(steps) || steps.length === 0) {
      return json({ error: "Challenge content is unavailable." }, 503);
    }

    if (action === "progress") {
      const currentStep = Number(input.current_step);
      if (!Number.isInteger(currentStep) ||
        currentStep !== attempt.current_step + 1 ||
        currentStep >= steps.length) {
        return json({ error: "Invalid challenge step." }, 400);
      }
      const activeStep = steps[attempt.current_step];
      if (activeStep?.type === "choose" || activeStep?.type === "listen") {
        const { data: answerEvent, error: answerError } = await admin
          .from("daily_challenge_step_events")
          .select("id")
          .eq("attempt_id", attemptId)
          .eq("user_id", userId)
          .eq("step_id", activeStep.id)
          .limit(1)
          .maybeSingle();
        if (answerError || !answerEvent) {
          return json({ error: "Answer the current question before continuing." }, 409);
        }
      }
      const { error } = await admin
        .from("daily_challenge_attempts")
        .update({
          current_step: currentStep,
          last_active_at: new Date().toISOString(),
        })
        .eq("id", attemptId)
        .eq("user_id", userId);
      if (error) return json({ error: "Could not save challenge progress." }, 503);
      return json({ ok: true });
    }

    if (action === "answer") {
      const stepId = String(input.step_id ?? "");
      const selectedIndex = Number(input.selected_index);
      const step = Array.isArray(steps)
        ? steps.find((candidate: Record<string, unknown>) => candidate.id === stepId)
        : null;
      if (steps[attempt.current_step]?.id !== stepId) {
        return json({ error: "Answer the current challenge step." }, 409);
      }
      const answer = version.answer_key_json?.[stepId];
      if (!step || !Number.isInteger(selectedIndex) ||
        selectedIndex < 0 || selectedIndex >= step.options?.length ||
        !Number.isInteger(answer?.index)) {
        return json({ error: "Invalid answer." }, 400);
      }
      const correct = selectedIndex === answer.index;
      const { error: eventError } = await admin
        .from("daily_challenge_step_events")
        .insert({
          attempt_id: attemptId,
          user_id: userId,
          step_id: stepId,
          selected_index: selectedIndex,
          is_correct: correct,
        });
      if (eventError) return json({ error: "Could not save this answer." }, 503);
      await admin
        .from("daily_challenge_attempts")
        .update({ last_active_at: new Date().toISOString() })
        .eq("id", attemptId)
        .eq("user_id", userId);
      return json({
        correct,
        explanation: String(answer.explanation ?? ""),
        correct_answer: String(step.options[answer.index]),
      });
    }

    if (action === "complete") {
      if (attempt.current_step !== steps.length - 1) {
        return json({ error: "Complete every challenge step first." }, 409);
      }
      const activeStep = steps[attempt.current_step];
      if (activeStep?.type === "choose" || activeStep?.type === "listen") {
        const { data: answerEvent, error: answerError } = await admin
          .from("daily_challenge_step_events")
          .select("id")
          .eq("attempt_id", attemptId)
          .eq("user_id", userId)
          .eq("step_id", activeStep.id)
          .limit(1)
          .maybeSingle();
        if (answerError || !answerEvent) {
          return json({ error: "Answer the final question before completing." }, 409);
        }
      }
      const seconds = Math.max(
        0,
        Math.floor((Date.now() - Date.parse(attempt.started_at ?? new Date().toISOString())) / 1000),
      );
      const { error } = await admin
        .from("daily_challenge_attempts")
        .update({
          status: "completed",
          completed_at: new Date().toISOString(),
          last_active_at: new Date().toISOString(),
          duration_seconds: seconds,
        })
        .eq("id", attemptId)
        .eq("user_id", userId);
      if (error) return json({ error: "Could not finish this challenge." }, 503);
      return json({ ok: true });
    }

    return json({ error: "Unknown action." }, 400);
  } catch (error) {
    console.error("Daily challenge request failed", error);
    return json({ error: "Daily challenge service is temporarily unavailable." }, 503);
  }
});
