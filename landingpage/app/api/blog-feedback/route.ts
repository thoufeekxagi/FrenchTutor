import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { getAllSlugs } from "../../blog/data";

export const runtime = "nodejs";

const validSlugs = new Set(getAllSlugs());

function getClient() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_ANON_KEY;
  if (!supabaseUrl || !supabaseKey) return null;
  return createClient(supabaseUrl, supabaseKey);
}

async function getCounts(supabase: NonNullable<ReturnType<typeof getClient>>, slug: string) {
  const [up, down] = await Promise.all([
    supabase.from("blog_post_feedback").select("id", { count: "exact", head: true }).eq("post_slug", slug).eq("vote", "up"),
    supabase.from("blog_post_feedback").select("id", { count: "exact", head: true }).eq("post_slug", slug).eq("vote", "down"),
  ]);
  return { up: up.count ?? 0, down: down.count ?? 0 };
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const slug = searchParams.get("slug");
  if (!slug || !validSlugs.has(slug)) {
    return NextResponse.json({ ok: false, message: "Unknown post." }, { status: 400 });
  }

  const supabase = getClient();
  if (!supabase) return NextResponse.json({ ok: true, up: 0, down: 0 });

  try {
    const counts = await getCounts(supabase, slug);
    return NextResponse.json({ ok: true, ...counts });
  } catch {
    return NextResponse.json({ ok: true, up: 0, down: 0 });
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { slug?: unknown; vote?: unknown };
    const slug = typeof body.slug === "string" ? body.slug : "";
    const vote = body.vote === "up" || body.vote === "down" ? body.vote : null;

    if (!validSlugs.has(slug) || !vote) {
      return NextResponse.json({ ok: false, message: "Invalid feedback." }, { status: 400 });
    }

    const supabase = getClient();
    if (!supabase) {
      return NextResponse.json({ ok: false, message: "Feedback is not configured yet." }, { status: 503 });
    }

    const { error } = await supabase.from("blog_post_feedback").insert({ post_slug: slug, vote });
    if (error) {
      return NextResponse.json({ ok: false, message: "Couldn't save that, please try again." }, { status: 502 });
    }

    const counts = await getCounts(supabase, slug);
    return NextResponse.json({ ok: true, ...counts });
  } catch {
    return NextResponse.json({ ok: false, message: "Couldn't save that, please try again." }, { status: 500 });
  }
}
