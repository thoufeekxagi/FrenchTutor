"use client";

import { useEffect, useState } from "react";
import { ThumbsUp, ThumbsDown } from "lucide-react";

type Vote = "up" | "down";
type State = "idle" | "loading" | "voted" | "error";

function storageKey(slug: string) {
  return `parlesprint_blog_vote_${slug}`;
}

export function PostFeedback({ slug }: { slug: string }) {
  const [upCount, setUpCount] = useState<number | null>(null);
  const [state, setState] = useState<State>("idle");
  const [myVote, setMyVote] = useState<Vote | null>(null);

  useEffect(() => {
    const stored = typeof window !== "undefined" ? window.localStorage.getItem(storageKey(slug)) : null;
    if (stored === "up" || stored === "down") setMyVote(stored);

    fetch(`/api/blog-feedback?slug=${encodeURIComponent(slug)}`)
      .then((res) => res.json())
      .then((data: { ok?: boolean; up?: number }) => {
        if (data.ok) setUpCount(data.up ?? 0);
      })
      .catch(() => setUpCount(0));
  }, [slug]);

  async function vote(choice: Vote) {
    if (myVote || state === "loading") return;
    setState("loading");
    try {
      const res = await fetch("/api/blog-feedback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ slug, vote: choice }),
      });
      const data = (await res.json()) as { ok?: boolean; up?: number };
      if (!res.ok || !data.ok) throw new Error();
      setUpCount(data.up ?? 0);
      setMyVote(choice);
      window.localStorage.setItem(storageKey(slug), choice);
      setState("voted");
    } catch {
      setState("error");
    }
  }

  return (
    <div className="mt-14 flex flex-col items-center gap-4 text-center">
      <p className="text-sm font-bold uppercase tracking-widest text-[#9ca3af]">Was this article helpful?</p>
      <div className="flex items-center gap-4">
        <button
          type="button"
          onClick={() => vote("up")}
          disabled={!!myVote}
          aria-pressed={myVote === "up"}
          className={`flex items-center gap-2 rounded-full border px-5 py-2.5 font-bold text-sm transition-colors ${
            myVote === "up"
              ? "bg-[#e7f6ec] border-[#28A745] text-[#28A745]"
              : "border-[#e5e7eb] text-[#33383F] hover:border-[#28A745]/50 hover:text-[#28A745]"
          } ${myVote && myVote !== "up" ? "opacity-50" : ""}`}
        >
          <ThumbsUp className="w-4 h-4" />
          Yes{upCount !== null ? ` (${upCount})` : ""}
        </button>
        <button
          type="button"
          onClick={() => vote("down")}
          disabled={!!myVote}
          aria-pressed={myVote === "down"}
          className={`flex items-center gap-2 rounded-full border px-5 py-2.5 font-bold text-sm transition-colors ${
            myVote === "down"
              ? "bg-[#fdecec] border-[#DC3545] text-[#DC3545]"
              : "border-[#e5e7eb] text-[#33383F] hover:border-[#DC3545]/50 hover:text-[#DC3545]"
          } ${myVote && myVote !== "down" ? "opacity-50" : ""}`}
        >
          <ThumbsDown className="w-4 h-4" />
          No
        </button>
      </div>
      {myVote && <p className="text-sm font-medium text-[#6b7280]">Thanks for the feedback.</p>}
      {state === "error" && <p className="text-sm font-semibold text-[#DC3545]">Couldn&apos;t save that, please try again.</p>}
    </div>
  );
}
