import Link from "next/link";
import { Logo } from "./logo";

/**
 * Shared site navigation, used on every page (homepage, blog, stories) so the chrome
 * never differs between pages. The anchor links point at "/#section" rather than a bare
 * "#section" so they resolve correctly from any page, not just the homepage.
 */
export function SiteNav() {
  return (
    <nav className="sticky top-0 w-full glass-nav z-50 transition-all duration-300">
      <div className="max-w-7xl mx-auto px-6 h-[72px] flex items-center justify-between">
        <Link href="/" className="group">
          <Logo size={34} />
        </Link>
        <div className="flex items-center gap-4 sm:gap-8 text-[15px] font-medium text-[#6b7280]">
          <div className="hidden md:flex items-center gap-8">
            <Link href="/#how-it-works" className="hover:text-[#1C1E21] transition-colors">The Loop</Link>
            <Link href="/#experience" className="hover:text-[#1C1E21] transition-colors">Experience</Link>
            <Link href="/#vs-tutor" className="hover:text-[#1C1E21] transition-colors">vs. a tutor</Link>
            <Link href="/#pricing" className="hover:text-[#1C1E21] transition-colors">Pricing</Link>
            <Link href="/#for-canada" className="hover:text-[#1C1E21] transition-colors">For Canada</Link>
          </div>
          <Link href="/blog" className="font-bold text-[#007BFF] hover:text-[#0062CC] transition-colors">Blog</Link>
          <Link href="/stories" className="font-bold text-[#007BFF] hover:text-[#0062CC] transition-colors">Stories</Link>
        </div>
        <Link
          href="/#join"
          className="bg-[#1C1E21] text-white px-5 py-2.5 rounded-full font-semibold text-sm hover:bg-[#33383F] hover:scale-105 transition-all shadow-md"
        >
          Join Waitlist
        </Link>
      </div>
    </nav>
  );
}
