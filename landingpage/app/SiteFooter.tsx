import Link from "next/link";
import { Logo } from "./logo";

/** Shared footer, used on every page so the chrome never differs between pages. */
export function SiteFooter() {
  return (
    <footer className="border-t border-[#e5e7eb] bg-white pt-16 pb-8">
      <div className="max-w-7xl mx-auto px-6 flex flex-col md:flex-row justify-between items-center gap-6">
        <Logo size={32} />
        <div className="flex items-center gap-6">
          <Link href="/blog" className="text-sm font-semibold text-[#007BFF] hover:underline">
            Read the blog
          </Link>
          <Link href="/stories" className="text-sm font-semibold text-[#007BFF] hover:underline">
            Learner stories
          </Link>
        </div>
        <p className="text-sm font-medium text-[#6b7280]">
          &copy; {new Date().getFullYear()} ParleSprint. Guided French practice for serious learners.
        </p>
      </div>
    </footer>
  );
}
