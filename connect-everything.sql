-- THOUGHTS & STORIES: connect public pages and the administrator studio.
-- Safe to run more than once. Does not delete or rewrite existing content.
-- Requires the existing public.is_blog_admin() function and profiles.role='admin'.

-- ARTICLES: visitors can read published stories; only the verified admin manages them.
ALTER TABLE public.articles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "TS public read published articles" ON public.articles;
CREATE POLICY "TS public read published articles" ON public.articles
  FOR SELECT TO anon, authenticated USING (published = true OR public.is_blog_admin());
DROP POLICY IF EXISTS "TS admin manage articles" ON public.articles;
CREATE POLICY "TS admin manage articles" ON public.articles
  FOR ALL TO authenticated USING (public.is_blog_admin()) WITH CHECK (public.is_blog_admin());
GRANT SELECT ON public.articles TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.articles TO authenticated;

-- BOOKS: keep admin CRUD and public visibility on the same table.
ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "TS public read published books" ON public.books;
CREATE POLICY "TS public read published books" ON public.books
  FOR SELECT TO anon, authenticated USING (published = true OR public.is_blog_admin());
DROP POLICY IF EXISTS "TS admin manage books" ON public.books;
CREATE POLICY "TS admin manage books" ON public.books
  FOR ALL TO authenticated USING (public.is_blog_admin()) WITH CHECK (public.is_blog_admin());
GRANT SELECT ON public.books TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.books TO authenticated;

-- COMMENTS: members can submit their own comments; public sees approved comments;
-- the administrator can approve, reply to, and delete comments.
ALTER TABLE public.story_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "TS public read approved comments" ON public.story_comments;
CREATE POLICY "TS public read approved comments" ON public.story_comments
  FOR SELECT TO anon, authenticated USING (approved = true OR public.is_blog_admin() OR user_id = auth.uid());
DROP POLICY IF EXISTS "TS members add own comments" ON public.story_comments;
CREATE POLICY "TS members add own comments" ON public.story_comments
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "TS admin manage comments" ON public.story_comments;
CREATE POLICY "TS admin manage comments" ON public.story_comments
  FOR ALL TO authenticated USING (public.is_blog_admin()) WITH CHECK (public.is_blog_admin());
GRANT SELECT ON public.story_comments TO anon, authenticated;
GRANT INSERT ON public.story_comments TO authenticated;
GRANT UPDATE, DELETE ON public.story_comments TO authenticated;

-- PROFILES: each member sees/updates their own profile; admin can manage/view all.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "TS members read own profile" ON public.profiles;
CREATE POLICY "TS members read own profile" ON public.profiles
  FOR SELECT TO authenticated USING (id = auth.uid() OR public.is_blog_admin());
DROP POLICY IF EXISTS "TS members update own profile" ON public.profiles;
CREATE POLICY "TS members update own profile" ON public.profiles
  FOR UPDATE TO authenticated USING (id = auth.uid() OR public.is_blog_admin())
  WITH CHECK (id = auth.uid() OR public.is_blog_admin());
GRANT SELECT, UPDATE ON public.profiles TO authenticated;

-- VISITS: visitors can record a page view; only admin can read analytics.
CREATE TABLE IF NOT EXISTS public.site_visits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  page_path text NOT NULL,
  visitor_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.site_visits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "TS record public visits" ON public.site_visits;
CREATE POLICY "TS record public visits" ON public.site_visits
  FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "TS admin read visits" ON public.site_visits;
CREATE POLICY "TS admin read visits" ON public.site_visits
  FOR SELECT TO authenticated USING (public.is_blog_admin());
GRANT INSERT ON public.site_visits TO anon, authenticated;
GRANT SELECT ON public.site_visits TO authenticated;

-- DONATION SETTINGS: enabled settings are public; only admin can edit them.
ALTER TABLE public.donation_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "TS public read enabled donations" ON public.donation_settings;
CREATE POLICY "TS public read enabled donations" ON public.donation_settings
  FOR SELECT TO anon, authenticated USING (enabled = true OR public.is_blog_admin());
DROP POLICY IF EXISTS "TS admin manage donations" ON public.donation_settings;
CREATE POLICY "TS admin manage donations" ON public.donation_settings
  FOR ALL TO authenticated USING (public.is_blog_admin()) WITH CHECK (public.is_blog_admin());
GRANT SELECT ON public.donation_settings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.donation_settings TO authenticated;

-- Gallery access is handled by the existing gallery setup migration included beside this file.
