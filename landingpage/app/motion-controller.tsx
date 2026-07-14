"use client";

import { ReactNode, useLayoutEffect } from "react";

const revealSelectors = [
  ".section-heading",
  ".identity-copy",
  ".reason-card",
  ".method-principles article",
  ".mode-card",
  ".pathway-copy",
  ".pathway-board",
  ".marie-demo",
  ".marie-copy",
  ".personal-layout > div",
  ".exam-copy",
  ".exam-ticket",
  ".founder-copy",
  ".founding-copy",
  ".founding-form",
  ".faq-heading",
  ".faq-list details",
].join(",");

export function MotionController({ children }: { children: ReactNode }) {
  useLayoutEffect(() => {
    const root = document.documentElement;
    root.classList.add("motion-ready");
    const targets = Array.from(document.querySelectorAll<HTMLElement>(revealSelectors));
    targets.forEach((target) => {
      target.classList.add("motion-reveal");
      const siblings = target.parentElement ? Array.from(target.parentElement.children) : [];
      target.style.setProperty("--reveal-order", String(Math.min(siblings.indexOf(target), 5)));
    });

    const observer = new IntersectionObserver(
      (entries) => entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }),
      { threshold: 0.12, rootMargin: "0px 0px -7%" },
    );
    targets.forEach((target) => observer.observe(target));

    let frame = 0;
    const updateScroll = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const distance = document.documentElement.scrollHeight - window.innerHeight;
        root.style.setProperty("--scroll-progress", String(distance > 0 ? window.scrollY / distance : 0));
        root.style.setProperty("--page-y", `${Math.min(window.scrollY, 900)}px`);
      });
    };

    const hero = document.querySelector<HTMLElement>(".hero-product");
    const moveHero = (event: PointerEvent) => {
      if (!hero || event.pointerType === "touch") return;
      const rect = hero.getBoundingClientRect();
      hero.style.setProperty("--pointer-x", `${((event.clientX - rect.left) / rect.width - .5) * 12}px`);
      hero.style.setProperty("--pointer-y", `${((event.clientY - rect.top) / rect.height - .5) * 12}px`);
    };
    const resetHero = () => {
      hero?.style.setProperty("--pointer-x", "0px");
      hero?.style.setProperty("--pointer-y", "0px");
    };

    updateScroll();
    window.addEventListener("scroll", updateScroll, { passive: true });
    hero?.addEventListener("pointermove", moveHero);
    hero?.addEventListener("pointerleave", resetHero);

    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", updateScroll);
      hero?.removeEventListener("pointermove", moveHero);
      hero?.removeEventListener("pointerleave", resetHero);
      root.classList.remove("motion-ready");
    };
  }, []);

  return <>{children}<div className="scroll-progress" aria-hidden="true" /></>;
}
