"use client";

import { useEffect } from "react";

export function ReadingProgress() {
  useEffect(() => {
    const update = () => {
      const documentHeight = document.documentElement.scrollHeight - window.innerHeight;
      const progress = documentHeight > 0 ? Math.min(100, Math.max(0, (window.scrollY / documentHeight) * 100)) : 0;
      document.documentElement.style.setProperty("--reading-progress", `${progress}%`);
    };

    update();
    window.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
    return () => {
      window.removeEventListener("scroll", update);
      window.removeEventListener("resize", update);
    };
  }, []);

  return <div className="article-progress" aria-hidden="true"><div className="article-progress-bar" /></div>;
}
