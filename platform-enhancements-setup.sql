-- THOUGHTS & STORIES PLATFORM ENHANCEMENTS

create table if not exists public.site_appearance (
  id bigint generated always as identity primary key,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now()
);

create table if not exists public.magazines (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  cover_url text,
  content_url text,
  category text,
  published boolean default false,
  published_at timestamptz,
  created_at timestamptz default now()
);

create table if not exists public.member_reading_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  theme text default 'light',
  font_size integer default 18,
  font_family text default 'serif',
  wallpaper_url text,
  brightness integer default 100,
  updated_at timestamptz default now()
);

create table if not exists public.reading_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id uuid,
  article_id uuid,
  progress numeric default 0,
  last_position text,
  updated_at timestamptz default now()
);

create table if not exists public.reading_bookmarks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id uuid,
  article_id uuid,
  location text,
  note text,
  created_at timestamptz default now()
);

create table if not exists public.game_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  category text,
  enabled boolean default true,
  created_at timestamptz default now()
);

create table if not exists public.game_scores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  game_name text not null,
  score integer not null default 0,
  level integer default 1,
  difficulty text default 'normal',
  created_at timestamptz default now()
);

insert into public.game_catalog (name, category, description)
values
('Snake Rush','Arcade','Classic snake game'),
('Fruit Slice','Arcade','Fruit slicing game'),
('Jewel Match','Puzzle','Match three jewels'),
('Block Puzzle','Puzzle','Block placement challenge'),
('Bubble Shooter','Arcade','Bubble shooting game'),
('Word Search','Word','Find hidden words'),
('Crossword','Word','Crossword puzzles'),
('Sudoku','Logic','Number logic puzzles'),
('Trivia Quiz','Quiz','General knowledge quiz'),
('Memory Match','Memory','Match hidden pairs'),
('Word Scramble','Word','Unscramble words'),
('Book Trivia','Quiz','Literature and book quizzes')
on conflict (name) do nothing;

alter table public.site_appearance enable row level security;
alter table public.magazines enable row level security;
alter table public.member_reading_preferences enable row level security;
alter table public.reading_progress enable row level security;
alter table public.reading_bookmarks enable row level security;
alter table public.game_catalog enable row level security;
alter table public.game_scores enable row level security;

drop policy if exists "Public can read appearance" on public.site_appearance;
create policy "Public can read appearance"
on public.site_appearance for select
using (true);

drop policy if exists "Admins manage appearance" on public.site_appearance;
create policy "Admins manage appearance"
on public.site_appearance for all
to authenticated
using (public.is_blog_admin())
with check (public.is_blog_admin());

drop policy if exists "Public can read published magazines" on public.magazines;
create policy "Public can read published magazines"
on public.magazines for select
using (published = true or public.is_blog_admin());

drop policy if exists "Admins manage magazines" on public.magazines;
create policy "Admins manage magazines"
on public.magazines for all
to authenticated
using (public.is_blog_admin())
with check (public.is_blog_admin());

drop policy if exists "Members manage own preferences" on public.member_reading_preferences;
create policy "Members manage own preferences"
on public.member_reading_preferences for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Members manage own progress" on public.reading_progress;
create policy "Members manage own progress"
on public.reading_progress for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Members manage own bookmarks" on public.reading_bookmarks;
create policy "Members manage own bookmarks"
on public.reading_bookmarks for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Public can read enabled games" on public.game_catalog;
create policy "Public can read enabled games"
on public.game_catalog for select
using (enabled = true or public.is_blog_admin());

drop policy if exists "Admins manage games" on public.game_catalog;
create policy "Admins manage games"
on public.game_catalog for all
to authenticated
using (public.is_blog_admin())
with check (public.is_blog_admin());

drop policy if exists "Public can view game scores" on public.game_scores;
create policy "Public can view game scores"
on public.game_scores for select
using (true);

drop policy if exists "Members submit own scores" on public.game_scores;
create policy "Members submit own scores"
on public.game_scores for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Admins manage game scores" on public.game_scores;
create policy "Admins manage game scores"
on public.game_scores for all
to authenticated
using (public.is_blog_admin())
with check (public.is_blog_admin());

grant select on public.site_appearance to anon, authenticated;
grant select on public.magazines to anon, authenticated;
grant select, insert, update, delete on public.member_reading_preferences to authenticated;
grant select, insert, update, delete on public.reading_progress to authenticated;
grant select, insert, update, delete on public.reading_bookmarks to authenticated;
grant select on public.game_catalog to anon, authenticated;
grant select, insert on public.game_scores to authenticated;
grant select on public.game_scores to anon;
