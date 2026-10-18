import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { SiteNav } from "../../SiteNav";
import { SiteFooter } from "../../SiteFooter";
import { PageIntro } from "../../../components/site-ui";
import { ToolWorkspace } from "../../../components/tool-workspace";
import { tools } from "../../../lib/practice";
export function generateStaticParams(){return tools.map(t=>({slug:t.slug}));}
export async function generateMetadata({params}:{params:Promise<{slug:string}>}):Promise<Metadata>{const {slug}=await params,t=tools.find(t=>t.slug===slug);return t?{title:`Free French ${t.title} | ParleSprint`,description:t.description,alternates:{canonical:`/tools/${slug}`}}:{};}
export default async function ToolPage({params}:{params:Promise<{slug:string}>}){const {slug}=await params,t=tools.find(t=>t.slug===slug);if(!t)notFound();return <><SiteNav/><main id="main-content" className="page-shell site-container"><PageIntro eyebrow={`FREE FRENCH TOOLS / ${t.category.toUpperCase()}`} title={t.title} description={t.description}/><ToolWorkspace slug={slug}/><p className="small-print">{t.detail}. <Link href="/tools">Explore all free tools</Link>.</p></main><SiteFooter/></>;}
