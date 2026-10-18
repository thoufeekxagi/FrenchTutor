import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { ToolIcon } from "../components/site-ui";
import { freeToolEntries } from "../lib/practice";
import { Logo } from "./logo";

const practiceLinks = [
  ["/today", "Daily practice"],
  ["/learn", "Guided lessons"],
  ["/stories", "Short stories"],
] as const;

const moreLinks = [
  ["/extension", "Chrome extension"],
  ["/app", "iPhone app"],
  ["/blog", "French journal"],
  ["/feedback", "Share feedback"],
  ["/support", "Help & support"],
] as const;

export function SiteFooter() {
  return (
    <footer className="site-footer" id="site-footer">
      <div className="footer-inner">
        <div className="footer-top">
          <div className="footer-brand">
            <Link className="footer-brand-home" href="/" aria-label="ParleSprint home">
              <Logo size={32} />
            </Link>
            <p>Small, useful French practice for the moments that make up your day.</p>
            <Link className="footer-practice-cta" href="/today">
              Start today’s practice <ArrowRight size={16} aria-hidden="true" />
            </Link>
            <span className="footer-free-note">Free to use · no account needed</span>
          </div>

          <nav className="footer-tools" aria-labelledby="footer-tools-title">
            <div className="footer-heading-row">
              <div>
                <p className="footer-label">Made for everyday French</p>
                <h2 id="footer-tools-title">10 free ways to practise</h2>
              </div>
              <Link className="footer-all-tools" href="/tools">
                Browse all <ArrowRight size={15} aria-hidden="true" />
              </Link>
            </div>
            <div className="footer-tools-grid">
              {freeToolEntries.map((tool) => (
                <Link className="footer-tool-link" href={tool.href} key={tool.href}>
                  <span className="footer-tool-icon"><ToolIcon name={tool.icon} /></span>
                  <span>{tool.title}</span>
                </Link>
              ))}
            </div>
          </nav>

          <nav className="footer-link-group" aria-label="Practice">
            <p className="footer-label">Keep learning</p>
            {practiceLinks.map(([href, label]) => <Link href={href} key={href}>{label}</Link>)}
          </nav>

          <nav className="footer-link-group" aria-label="More from ParleSprint">
            <p className="footer-label">More from ParleSprint</p>
            {moreLinks.map(([href, label]) => <Link href={href} key={href}>{label}</Link>)}
          </nav>
        </div>

        <div className="footer-bottom">
          <span>© {new Date().getFullYear()} ParleSprint</span>
          <span>Independent French learning tools · Not affiliated with FEI or IRCC</span>
          <nav aria-label="Legal and support">
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
            <Link href="/support">Support</Link>
          </nav>
        </div>
      </div>
    </footer>
  );
}
