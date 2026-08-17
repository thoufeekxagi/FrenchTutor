-- Persist generated grammar-story cover URLs alongside the grammar lesson.
alter table public.generated_grammar_stories
  add column if not exists cover_url text;
