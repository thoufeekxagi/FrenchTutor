"use client";

import { useEffect, useRef, type ReactNode } from "react";

export function Reveal({ children, className = "" }: { children: ReactNode; className?: string }) {
  const element = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window)) return;
    const target = element.current;
    if (!target) return;
    target.classList.add("scroll-reveal-armed");
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        target.classList.add("scroll-reveal-visible");
        observer.disconnect();
      }
    }, { threshold: 0.12, rootMargin: "0px 0px -36px 0px" });
    observer.observe(target);
    return () => {
      observer.disconnect();
      target.classList.remove("scroll-reveal-armed", "scroll-reveal-visible");
    };
  }, []);

  return <div ref={element} className={`scroll-reveal ${className}`}>{children}</div>;
}
