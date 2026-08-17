-- Keep generated roleplay artwork on the same learner-owned private cover
-- path used by reading, listening, grammar, and writing content.
alter table public.generated_roleplays
  add column if not exists cover_url text;
