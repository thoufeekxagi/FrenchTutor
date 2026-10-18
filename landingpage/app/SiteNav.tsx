"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { Menu, MessageSquare, X } from "lucide-react";
import { Logo } from "./logo";
import { useLearner } from "../components/learner-provider";

const nav = [
  ["/today", "Daily practice"],
  ["/learn", "Learn"],
  ["/tools", "Free tools"],
  ["/extension", "Extension"],
  ["/app", "The app"],
] as const;

export function SiteNav() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const { user } = useLearner();
  const isCurrent = (href: string) => pathname === href || pathname.startsWith(`${href}/`);

  return (
    <>
      <a className="skip-link" href="#main-content">Skip to content</a>
      <header className="site-header">
        <div className="header-inner">
          <Link href="/" aria-label="ParleSprint home"><Logo size={30} /></Link>
          <nav className="desktop-nav" aria-label="Main navigation">
            {nav.map(([href, label]) => <Link key={href} href={href} aria-current={isCurrent(href) ? "page" : undefined}>{label}</Link>)}
          </nav>
          <div className="header-actions">
            <Link className="word-link" href="/words">My words</Link>
            <Link className="icon-button feedback-nav" href="/feedback" aria-label="Send feedback"><MessageSquare size={19} /></Link>
            <Link className="button button-small button-dark" href="/account">{user ? "My account" : "Sign in"}</Link>
            <button className="icon-button menu-toggle" type="button" aria-label={open ? "Close navigation" : "Open navigation"} aria-expanded={open} onClick={() => setOpen(!open)}>
              {open ? <X size={21} /> : <Menu size={21} />}
            </button>
          </div>
        </div>
        {open && <nav className="mobile-nav" aria-label="Mobile navigation">
          {nav.map(([href, label]) => <Link key={href} onClick={() => setOpen(false)} href={href} aria-current={isCurrent(href) ? "page" : undefined}>{label}</Link>)}
          <Link href="/words" onClick={() => setOpen(false)}>My words</Link>
          <Link href="/feedback" onClick={() => setOpen(false)}>Send feedback</Link>
        </nav>}
      </header>
    </>
  );
}
