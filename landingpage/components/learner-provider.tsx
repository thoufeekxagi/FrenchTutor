"use client";
import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import type { User } from "@supabase/supabase-js";
import { getBrowserClient } from "../lib/auth";
import { defaultPreferences, mergeWords, readLocal, writeLocal, type Preferences, type SavedWord } from "../lib/local";
type Learner = { ready:boolean;user:User|null;words:SavedWord[];prefs:Preferences;notice:string;syncState:string;saveWord:(text:string,meaning:string,sentence:string)=>void;removeWord:(id:string)=>void;setPreferences:(p:Partial<Preferences>)=>void;sync:()=>Promise<void>;importGuest:()=>void;signOut:()=>Promise<void> };
const Context=createContext<Learner|null>(null);
export function LearnerProvider({children}:{children:ReactNode}){
 const [ready,setReady]=useState(false),[user,setUser]=useState<User|null>(null),[words,setWords]=useState<SavedWord[]>([]),[prefs,setPrefs]=useState(defaultPreferences),[notice,setNotice]=useState(""),[syncState,setSyncState]=useState("Local only");
 const owner=useRef("guest"),currentWords=useRef<SavedWord[]>([]),version=useRef(0),syncing=useRef(false);
 const persist=useCallback((next:SavedWord[])=>{currentWords.current=next;setWords(next);try{writeLocal(`ps.words.v1.${owner.current}`,next);}catch{setNotice("Browser storage is full or unavailable. Export your words before leaving.");}},[]);
 const sync=useCallback(async()=>{
  const own=owner.current;if(own==="guest"||syncing.current)return;syncing.current=true;setSyncState("Syncing…");const revision=version.current;
  try{const client=await getBrowserClient();const {data,error}=await client.from("web_learning_items").select("item_id,payload,updated_at").eq("user_id",own).limit(2000);if(error)throw error;if(revision!==version.current)return;
   const remote=(data??[]).map(r=>({...r.payload,id:r.item_id,updatedAt:r.updated_at})) as SavedWord[];const combined=mergeWords(currentWords.current,remote);persist(combined);
   if(combined.length){const {error:writeError}=await client.from("web_learning_items").upsert(combined.map(w=>({user_id:own,item_id:w.id,payload:w,updated_at:w.updatedAt})),{onConflict:"user_id,item_id"});if(writeError)throw writeError;}
   if(revision===version.current)setSyncState("Synced to your account");
  }catch{if(revision===version.current)setSyncState("Saved here. Sync unavailable; try again.");}finally{syncing.current=false;}
 },[persist]);
 useEffect(()=>{let alive=true,unsubscribe:(()=>void)|undefined;queueMicrotask(()=>{if(!alive)return;const raw=readLocal<Partial<Preferences>>("ps.preferences.v1",{});setPrefs({...defaultPreferences,...raw,level:["A1","A2","B1","B2"].includes(String(raw.level))?raw.level!:"A1"});persist(mergeWords(readLocal<SavedWord[]>("ps.words.v1.guest",[]),[]));setReady(true);});
  getBrowserClient().then(async client=>{const apply=(nextUser:User|null)=>{if(!alive)return;const id=nextUser?.id??"guest";if(owner.current!==id){version.current++;owner.current=id;persist(mergeWords(readLocal<SavedWord[]>(`ps.words.v1.${id}`,[]),[]));}setUser(nextUser);if(nextUser)void sync();else setSyncState("Local only");};const {data}=await client.auth.getSession();apply(data.session?.user??null);const {data:listener}=client.auth.onAuthStateChange((_event,session)=>{queueMicrotask(()=>apply(session?.user??null));});unsubscribe=()=>listener.subscription.unsubscribe();}).catch(()=>{});return()=>{alive=false;unsubscribe?.();};
 },[persist,sync]);
 useEffect(()=>{document.documentElement.dataset.largeText=String(prefs.largeText);document.documentElement.dataset.reducedMotion=String(prefs.reducedMotion);},[prefs]);
 const update=(next:SavedWord[])=>{persist(next);if(owner.current!=="guest")void sync();};
 const saveWord=(text:string,meaning:string,sentence:string)=>{const id=text.normalize("NFC").toLocaleLowerCase("fr").trim();if(!id)return;update([...currentWords.current.filter(x=>x.id!==id),{id,text,meaning,sentence,updatedAt:new Date().toISOString()}].slice(-2000));};
 const removeWord=(id:string)=>update(currentWords.current.map(w=>w.id===id?{...w,deleted:true,updatedAt:new Date().toISOString()}:w));
 const setPreferences=(patch:Partial<Preferences>)=>{setPrefs(old=>{const next={...old,...patch};try{writeLocal("ps.preferences.v1",next);}catch{setNotice("This browser could not save your settings.");}return next;});window.dispatchEvent(new Event("ps-preferences"));};
 const importGuest=()=>{if(owner.current==="guest")return;update(mergeWords(readLocal<SavedWord[]>("ps.words.v1.guest",[]),currentWords.current));setNotice("Guest words added to this account. The guest copy stays on this browser until you clear browser data.");};
 const signOut=async()=>{try{const c=await getBrowserClient();const {error}=await c.auth.signOut({scope:"local"});if(error)throw error;}catch{setNotice("Could not sign out. Please try again.");}};
 return <Context.Provider value={{ready,user,words:words.filter(w=>!w.deleted),prefs,notice,syncState,saveWord,removeWord,setPreferences,sync,importGuest,signOut}}>{children}</Context.Provider>;
}
export function useLearner(){const v=useContext(Context);if(!v)throw Error("Missing learner provider");return v;}
