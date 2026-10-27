-- Cloud storage for Svenska: run once in the Supabase dashboard › SQL Editor.
-- Every table is private to its owner through row-level security; the app only ever uses the
-- public anon (publishable) key plus the signed-in user's token.
-- The bundled dictionary and word lists stay on the device; only the learner's own data is stored here.

-- Bumps updated_at on every write, so devices can ask for "everything changed since …".
create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;

-- Saved words with their spaced-repetition state. Deleted words are kept as tombstones (deleted = true)
-- so the deletion reaches the learner's other devices.
create table if not exists public.saved_words (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  key text not null,
  word text not null default '',
  part_of_speech text not null default '',
  gender text not null default '',
  forms text not null default '',
  translation text not null default '',
  example text not null default '',
  example_translation text not null default '',
  note text not null default '',
  source text not null default '',
  level text not null default '',
  added_at timestamptz,
  is_favorite boolean not null default false,
  ease_factor double precision not null default 2.5,
  interval_days integer not null default 0,
  repetitions integer not null default 0,
  lapses integer not null default 0,
  review_count integer not null default 0,
  due_date timestamptz,
  last_reviewed_at timestamptz,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

-- Review history (append-only). id is "<word key>|<milliseconds since 1970>".
create table if not exists public.review_logs (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  id text not null,
  word_key text not null,
  grade smallint not null,
  interval_after integer not null default 0,
  reviewed_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);
-- The review method used (flashcards, reverse, choice, listening, spelling), so mixed review can favour each word's
-- weak methods on every device. Empty for answers logged before this column existed.
alter table public.review_logs add column if not exists mode text not null default '';

-- Daily check-ins; day is the learner's local calendar day.
create table if not exists public.check_ins (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  day date not null,
  checked_in_at timestamptz,
  items_done integer not null default 0,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

-- Preferences shared across devices (daily goal, session size, speech, skipped words, …).
create table if not exists public.user_settings (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  key text not null default 'settings',
  data jsonb not null default '{}',
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

-- Word lists the learner imported (deck_*.tsv files), stored as text.
create table if not exists public.imported_lists (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  file_name text not null,
  content text not null default '',
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, file_name)
);

do $$
declare t text;
begin
  foreach t in array array['saved_words', 'review_logs', 'check_ins', 'user_settings', 'imported_lists'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "Owner only" on public.%I', t);
    execute format('create policy "Owner only" on public.%I for all to authenticated
                    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('drop trigger if exists touch_updated_at on public.%I', t);
    execute format('create trigger touch_updated_at before insert or update on public.%I
                    for each row execute function public.touch_updated_at()', t);
    execute format('create index if not exists %I on public.%I (user_id, updated_at)', t || '_changes', t);
  end loop;
end $$;

-- Lets a signed-in learner delete their own account; their rows go with it (on delete cascade).
create or replace function public.delete_account() returns void
language sql security definer set search_path = '' as $$
  delete from auth.users where id = auth.uid();
$$;
revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
