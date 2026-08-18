-- Keep the generated roleplay card truthful when a learner changes level
-- after creating a scene.
alter table public.generated_roleplays
  add column if not exists level_band text not null default 'A1';
