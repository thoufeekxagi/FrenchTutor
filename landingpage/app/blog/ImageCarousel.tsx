"use client";

import { useState } from "react";
import Image from "next/image";
import { ChevronLeft, ChevronRight } from "lucide-react";

export function ImageCarousel({ images }: { images: { src: string; alt: string; caption?: string }[] }) {
  const [index, setIndex] = useState(0);
  if (images.length === 0) return null;
  const current = images[index];

  return (
    <figure className="my-2">
      <div className="relative w-full aspect-video rounded-3xl overflow-hidden border border-[#e5e7eb] bg-[#F8F9FA]">
        <Image src={current.src} alt={current.alt} fill className="object-cover" sizes="(max-width: 768px) 100vw, 768px" />
        {images.length > 1 && (
          <>
            <button
              type="button"
              aria-label="Previous image"
              onClick={() => setIndex((i) => (i - 1 + images.length) % images.length)}
              className="absolute left-3 top-1/2 -translate-y-1/2 flex h-9 w-9 items-center justify-center rounded-full bg-white/90 text-[#1C1E21] shadow-md hover:bg-white transition-colors"
            >
              <ChevronLeft className="w-5 h-5" />
            </button>
            <button
              type="button"
              aria-label="Next image"
              onClick={() => setIndex((i) => (i + 1) % images.length)}
              className="absolute right-3 top-1/2 -translate-y-1/2 flex h-9 w-9 items-center justify-center rounded-full bg-white/90 text-[#1C1E21] shadow-md hover:bg-white transition-colors"
            >
              <ChevronRight className="w-5 h-5" />
            </button>
            <div className="absolute bottom-3 left-1/2 -translate-x-1/2 flex gap-1.5">
              {images.map((_, i) => (
                <button
                  key={i}
                  type="button"
                  aria-label={`Go to image ${i + 1}`}
                  onClick={() => setIndex(i)}
                  className={`h-1.5 rounded-full transition-all ${i === index ? "w-5 bg-white" : "w-1.5 bg-white/60"}`}
                />
              ))}
            </div>
          </>
        )}
      </div>
      {current.caption && <figcaption className="mt-3 text-sm text-center text-[#6b7280] font-medium">{current.caption}</figcaption>}
    </figure>
  );
}
