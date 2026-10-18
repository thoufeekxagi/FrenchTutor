import { NextResponse } from "next/server";
export const dynamic = "force-dynamic";
export async function GET() {
  const url=process.env.SUPABASE_URL, key=process.env.SUPABASE_ANON_KEY;
  if(!url||!key) return NextResponse.json({message:"Account connection unavailable"},{status:503});
  // Only the public anonymous key crosses this boundary. Never return service-role credentials.
  return NextResponse.json({url,key},{headers:{"Cache-Control":"no-store"}});
}
