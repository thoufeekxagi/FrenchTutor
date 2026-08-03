-- Public, immutable French alphabet audio catalog. The Flutter app ships the
-- same PCM files for offline first-run playback; this table and Storage bucket
-- are the central source for publishing/versioning the catalog.
create table public.alphabet_audio_catalog (
  asset_key text primary key,
  persona_id text not null check (persona_id in ('marie', 'julien', 'camille', 'mathieu')),
  voice_name text not null,
  accent text not null,
  content_item_id text not null,
  letter text not null,
  spoken_text text not null,
  asset_path text not null,
  storage_path text not null unique,
  sha256 text not null,
  bytes integer not null check (bytes > 0),
  sample_rate_hz integer not null default 24000,
  channels integer not null default 1,
  encoding text not null default 'pcm_s16le',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.alphabet_audio_catalog is
  'Public pre-generated French alphabet and accent clips for all four tutor voices; no learner-specific data.';

alter table public.alphabet_audio_catalog enable row level security;

create policy "anyone can read alphabet audio catalog"
on public.alphabet_audio_catalog
for select
using (true);

grant select on table public.alphabet_audio_catalog to anon, authenticated;

insert into storage.buckets (id, name, public)
values ('alphabet-audio', 'alphabet-audio', true)
on conflict (id) do update set public = excluded.public;

create policy "anyone can read alphabet audio"
on storage.objects
for select
using (bucket_id = 'alphabet-audio');
