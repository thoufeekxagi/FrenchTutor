import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { SiteNav } from "../SiteNav";
import { SiteFooter } from "../SiteFooter";
import { PageIntro, ToolCards, FreeNote } from "../../components/site-ui";
export const metadata:Metadata={title:"Free French learning tools | ParleSprint",description:"Try ten free ways to practise French: daily challenges, guided lessons, verbs, reading, writing, listening, conversation and more. No signup required.",alternates:{canonical:"/tools"}};
export default function ToolsPage(){return <><SiteNav/><main id="main-content" className="page-shell site-container"><PageIntro eyebrow="YOUR EVERYDAY TOOLKIT" title="Ten free ways to practise French." description="Start with a daily challenge, then choose the kind of practice that fits your day. Everything here works without an account; your drafts and saved phrases stay on this browser until you choose to sync."/><ToolCards/><FreeNote/><section className="panel" style={{marginTop:40}}><h2>Not sure where to begin?</h2><p className="muted">Start with three short questions at your level. No test pressure, just a useful place to start.</p><Link href="/today" className="text-link">Try today’s practice <ArrowRight size={16}/></Link></section></main><SiteFooter/></>;}
