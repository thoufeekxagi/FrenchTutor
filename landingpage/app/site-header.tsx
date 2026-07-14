"use client";

import Image from "next/image";
import { Menu, X } from "lucide-react";
import { useState } from "react";

export function SiteHeader() {
  const [open, setOpen] = useState(false);
  const close = () => setOpen(false);

  return (
    <>
      <div className="announcement">
        <span className="signal-dot" />
        <span>Founding learner pilot opening soon</span>
        <a href="#founding">Apply for access</a>
      </div>
      <header className="site-header shell">
        <a className="brand" href="#top" aria-label="ParleSprint home" onClick={close}>
          <Image src="/parle-mark.svg" alt="" width={36} height={36} priority />
          <span>Parle<span>Sprint</span></span>
        </a>
        <nav className={open ? "main-nav is-open" : "main-nav"} aria-label="Main navigation">
          <a href="#method" onClick={close}>Method</a>
          <a href="#modes" onClick={close}>Practice modes</a>
          <a href="#marie" onClick={close}>Marie</a>
          <a href="#exams" onClick={close}>TEF / TCF</a>
          <a className="nav-cta" href="#founding" onClick={close}>Apply now</a>
        </nav>
        <button className="menu-button" type="button" aria-label={open ? "Close menu" : "Open menu"} aria-expanded={open} onClick={() => setOpen(!open)}>
          {open ? <X size={22} /> : <Menu size={22} />}
        </button>
      </header>
    </>
  );
}
