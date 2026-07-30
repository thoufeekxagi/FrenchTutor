import Image from "next/image";
import type { ContentBlock } from "./data";
import { ImageCarousel } from "./ImageCarousel";

function embedUrl(src: string): string | null {
  const youtubeMatch = src.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([\w-]+)/);
  if (youtubeMatch) return `https://www.youtube-nocookie.com/embed/${youtubeMatch[1]}`;
  return null;
}

export function BlogProse({ content }: { content: ContentBlock[] }) {
  return (
    <div className="flex flex-col gap-6">
      {content.map((block, idx) => {
        switch (block.type) {
          case "h2":
            return (
              <h2 key={idx} className="mt-6 text-2xl md:text-3xl font-extrabold text-[#1C1E21] tracking-tight">
                {block.text}
              </h2>
            );
          case "h3":
            return (
              <h3 key={idx} className="mt-2 text-xl font-bold text-[#1C1E21] tracking-tight">
                {block.text}
              </h3>
            );
          case "p":
            return (
              <p key={idx} className="text-lg text-[#33383F] leading-relaxed">
                {block.text}
              </p>
            );
          case "ul":
            return (
              <ul key={idx} className="flex flex-col gap-3 pl-1">
                {block.items.map((item, i) => (
                  <li key={i} className="flex items-start gap-3 text-lg text-[#33383F] leading-relaxed">
                    <span className="mt-3 h-1.5 w-1.5 rounded-full bg-[#007BFF] shrink-0" />
                    <span>{item}</span>
                  </li>
                ))}
              </ul>
            );
          case "ol":
            return (
              <ol key={idx} className="flex flex-col gap-3 pl-1">
                {block.items.map((item, i) => (
                  <li key={i} className="flex items-start gap-3 text-lg text-[#33383F] leading-relaxed">
                    <span className="font-bold text-[#007BFF] shrink-0">{i + 1}.</span>
                    <span>{item}</span>
                  </li>
                ))}
              </ol>
            );
          case "quote":
            return (
              <blockquote key={idx} className="border-l-4 border-[#007BFF] pl-6 py-1">
                <p className="text-xl italic text-[#1C1E21] leading-relaxed">&ldquo;{block.text}&rdquo;</p>
                {block.attribution && <p className="mt-2 text-sm font-semibold text-[#6b7280]">{block.attribution}</p>}
              </blockquote>
            );
          case "callout":
            return (
              <div key={idx} className="rounded-3xl bg-[#F8F9FA] border border-[#e5e7eb] p-6 md:p-8">
                <p className="text-lg text-[#1C1E21] leading-relaxed font-medium">{block.text}</p>
              </div>
            );
          case "image":
            return (
              <figure key={idx} className="my-2">
                <div className="relative w-full aspect-video rounded-3xl overflow-hidden border border-[#e5e7eb]">
                  <Image src={block.src} alt={block.alt} fill className="object-cover" sizes="(max-width: 768px) 100vw, 768px" />
                </div>
                {block.caption && (
                  <figcaption className="mt-3 text-sm text-center text-[#6b7280] font-medium">{block.caption}</figcaption>
                )}
              </figure>
            );
          case "carousel":
            return <ImageCarousel key={idx} images={block.images} />;
          case "video": {
            const embed = embedUrl(block.src);
            return (
              <figure key={idx} className="my-2">
                <div className="relative w-full aspect-video rounded-3xl overflow-hidden border border-[#e5e7eb] bg-black">
                  {embed ? (
                    <iframe
                      src={embed}
                      title={block.caption ?? "Embedded video"}
                      className="absolute inset-0 h-full w-full"
                      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                      allowFullScreen
                    />
                  ) : (
                    <video controls poster={block.poster} className="absolute inset-0 h-full w-full object-cover">
                      <source src={block.src} />
                    </video>
                  )}
                </div>
                {block.caption && (
                  <figcaption className="mt-3 text-sm text-center text-[#6b7280] font-medium">{block.caption}</figcaption>
                )}
              </figure>
            );
          }
          default:
            return null;
        }
      })}
    </div>
  );
}
