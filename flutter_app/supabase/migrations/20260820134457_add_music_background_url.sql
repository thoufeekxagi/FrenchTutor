alter table public.generated_stories
  add column if not exists music_background_url text;
