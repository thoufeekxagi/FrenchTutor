import { createClient, type SupabaseClient } from "@supabase/supabase-js";
let client: Promise<SupabaseClient> | undefined;
export function getBrowserClient() {
  if (!client) client = fetch("/api/auth-config", { cache: "no-store" }).then(async r=>{ if(!r.ok) throw Error("Account connection is unavailable. Please try again shortly."); const c=await r.json(); return createClient(c.url,c.key,{auth:{flowType:"pkce",detectSessionInUrl:false,persistSession:true,autoRefreshToken:true}}); }).catch(e=>{client=undefined;throw e;});
  return client;
}
