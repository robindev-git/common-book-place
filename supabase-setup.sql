-- Common Book Place — Supabase schema setup
-- Run this ONCE in your Supabase project: SQL Editor > New query > paste > Run

create table if not exists word_counts (
  word text primary key,
  count integer not null default 0
);

create table if not exists used_emails (
  email_hash text primary key,
  word text not null,
  created_at timestamptz not null default now()
);

alter table word_counts enable row level security;
alter table used_emails enable row level security;

-- Anyone can read the word counts — this is the public "wall".
create policy "public can read word counts"
  on word_counts for select
  using (true);

-- Note: no policy is created for used_emails, so the client can
-- never read or write it directly. It's only touched by the
-- function below, which runs with elevated privileges.

-- Atomic "write a word": increments the count and records the
-- email hash in a single transaction, so two people submitting
-- at the exact same instant can't race each other or double-count.
create or replace function write_word(p_word text, p_email_hash text)
returns table(word text, count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if exists (select 1 from used_emails where email_hash = p_email_hash) then
    raise exception 'EMAIL_USED';
  end if;

  insert into word_counts (word, count)
  values (p_word, 1)
  on conflict (word) do update set count = word_counts.count + 1
  returning word_counts.count into v_count;

  insert into used_emails (email_hash, word) values (p_email_hash, p_word);

  return query select p_word, v_count;
end;
$$;

-- Let the public (anon) role call the function above.
grant execute on function write_word(text, text) to anon;
