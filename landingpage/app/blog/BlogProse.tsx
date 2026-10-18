import Image from "next/image";
import type { ContentBlock } from "./data";
import { ImageCarousel } from "./ImageCarousel";

function inlineText(text: string) {
  const parts = text.split(/(\*\*[^*]+\*\*|\*[^*]+\*|\[[^\]]+\]\([^\)]+\))/g);
  return parts.map((part, index) => {
    if (part.startsWith("**") && part.endsWith("**")) return <strong key={index}>{part.slice(2, -2)}</strong>;
    if (part.startsWith("*") && part.endsWith("*")) return <em key={index}>{part.slice(1, -1)}</em>;
    const link = part.match(/^\[([^\]]+)\]\(([^\)]+)\)$/);
    if (link) return <a key={index} href={link[2]} target={link[2].startsWith("http") ? "_blank" : undefined} rel={link[2].startsWith("http") ? "noreferrer" : undefined}>{link[1]}</a>;
    return part;
  });
}

function embedUrl(src: string): string | null {
  const youtubeMatch = src.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([\w-]+)/);
  return youtubeMatch ? `https://www.youtube-nocookie.com/embed/${youtubeMatch[1]}` : null;
}

export function headingId(text: string): string {
  return `section-${text.normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("en").replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "")}`;
}

export function BlogProse({ content }: { content: ContentBlock[] }) {
  return <div className="article-prose">{content.map((block, index) => {
    switch (block.type) {
      case "h2": return <h2 key={index} id={headingId(block.text)}>{block.text}</h2>;
      case "h3": return <h3 key={index} id={headingId(block.text)}>{block.text}</h3>;
      case "p": return <p key={index}>{inlineText(block.text)}</p>;
      case "ul": return <ul key={index}>{block.items.map((item, itemIndex) => <li key={itemIndex}>{inlineText(item)}</li>)}</ul>;
      case "ol": return <ol key={index}>{block.items.map((item, itemIndex) => <li key={itemIndex}>{inlineText(item)}</li>)}</ol>;
      case "quote": return <blockquote key={index}><p>&ldquo;{inlineText(block.text)}&rdquo;</p>{block.attribution && <p className="!mt-2 !font-sans !text-sm !text-[#415A74]">{inlineText(block.attribution)}</p>}</blockquote>;
      case "callout": return <div key={index} className="article-callout">{inlineText(block.text)}</div>;
      case "takeaway": return <aside key={index} className="article-takeaway"><p className="article-block-label">{inlineText(block.label)}</p><h3>{inlineText(block.title)}</h3><ul>{block.items.map((item, itemIndex) => <li key={itemIndex}>{inlineText(item)}</li>)}</ul></aside>;
      case "table": return <figure key={index} className="article-table-figure"><div className="article-table-wrap"><table><thead><tr>{block.headers.map((header) => <th key={header} scope="col">{inlineText(header)}</th>)}</tr></thead><tbody>{block.rows.map((row, rowIndex) => <tr key={rowIndex}>{row.map((cell, cellIndex) => <td key={`${rowIndex}-${cellIndex}`}>{inlineText(cell)}</td>)}</tr>)}</tbody></table></div>{block.caption && <figcaption>{inlineText(block.caption)}</figcaption>}</figure>;
      case "comparison": return <div key={index} className="article-comparison"><div className="article-comparison-card article-comparison-card-blue"><p className="article-block-label">{inlineText(block.left.title)}</p><ul>{block.left.items.map((item, itemIndex) => <li key={itemIndex}>{inlineText(item)}</li>)}</ul></div><div className="article-comparison-card article-comparison-card-ink"><p className="article-block-label">{inlineText(block.right.title)}</p><ul>{block.right.items.map((item, itemIndex) => <li key={itemIndex}>{inlineText(item)}</li>)}</ul></div></div>;
      case "practice": return <section key={index} className="article-practice"><p className="article-block-label">{inlineText(block.label)}</p><h3>{inlineText(block.prompt)}</h3><ol>{block.steps.map((step, stepIndex) => <li key={stepIndex}>{inlineText(step)}</li>)}</ol>{block.answer && <details><summary>Open a model answer</summary><p>{inlineText(block.answer)}</p></details>}</section>;
      case "image": return <figure key={index}><div className="relative aspect-video overflow-hidden rounded-2xl border border-[#10253F]/10"><Image src={block.src} alt={block.alt} fill className="object-cover" sizes="(max-width: 760px) 100vw, 760px" /></div>{block.caption && <figcaption className="mt-3 text-center text-sm text-[#415A74]">{block.caption}</figcaption>}</figure>;
      case "carousel": return <ImageCarousel key={index} images={block.images} />;
      case "video": {
        const embed = embedUrl(block.src);
        return <figure key={index}><div className="relative aspect-video overflow-hidden rounded-2xl bg-[#10253F]">{embed ? <iframe src={embed} title={block.caption ?? "Embedded video"} className="absolute inset-0 h-full w-full" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowFullScreen /> : <video controls poster={block.poster} className="absolute inset-0 h-full w-full object-cover"><source src={block.src} /></video>}</div>{block.caption && <figcaption className="mt-3 text-center text-sm text-[#415A74]">{block.caption}</figcaption>}</figure>;
      }
      default: return null;
    }
  })}</div>;
}
