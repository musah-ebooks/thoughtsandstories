-- Thoughts & Stories: BookZone, book-specific reader comments, member chat and Watch & Listen.
-- Safe to run repeatedly. Requires the existing public.is_blog_admin() function.

-- Book listings: free online titles and purchase editions.
ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS access_type text NOT NULL DEFAULT 'free',
  ADD COLUMN IF NOT EXISTS price numeric(12,2),
  ADD COLUMN IF NOT EXISTS purchase_url text;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'books_access_type_check'
      AND conrelid = 'public.books'::regclass
  ) THEN
    ALTER TABLE public.books
      ADD CONSTRAINT books_access_type_check
      CHECK (access_type IN ('free','purchase'));
  END IF;
END $$;

-- Each book has its own moderated public comments.
CREATE TABLE IF NOT EXISTS public.book_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL DEFAULT 'Reader',
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 4000),
  approved boolean NOT NULL DEFAULT false,
  admin_reply text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.book_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "TS public read approved book comments" ON public.book_comments;
CREATE POLICY "TS public read approved book comments" ON public.book_comments
  FOR SELECT TO anon, authenticated
  USING (approved = true OR user_id = auth.uid() OR public.is_blog_admin());
DROP POLICY IF EXISTS "TS members add own book comments" ON public.book_comments;
CREATE POLICY "TS members add own book comments" ON public.book_comments
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "TS admin manage book comments" ON public.book_comments;
CREATE POLICY "TS admin manage book comments" ON public.book_comments
  FOR ALL TO authenticated
  USING (public.is_blog_admin()) WITH CHECK (public.is_blog_admin());
GRANT SELECT ON public.book_comments TO anon, authenticated;
GRANT INSERT ON public.book_comments TO authenticated;
GRANT UPDATE, DELETE ON public.book_comments TO authenticated;

-- A member-only discussion room for each book.
CREATE TABLE IF NOT EXISTS public.book_chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL DEFAULT 'Reader',
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS book_chat_messages_book_created_idx
  ON public.book_chat_messages(book_id, created_at);
ALTER TABLE public.book_chat_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "TS members read book discussions" ON public.book_chat_messages;
CREATE POLICY "TS members read book discussions" ON public.book_chat_messages
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "TS members send book discussion messages" ON public.book_chat_messages;
CREATE POLICY "TS members send book discussion messages" ON public.book_chat_messages
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "TS admin moderate book discussions" ON public.book_chat_messages;
CREATE POLICY "TS admin moderate book discussions" ON public.book_chat_messages
  FOR ALL TO authenticated USING (public.is_blog_admin()) WITH CHECK (public.is_blog_admin());
GRANT SELECT, INSERT ON public.book_chat_messages TO authenticated;
GRANT UPDATE, DELETE ON public.book_chat_messages TO authenticated;

-- Watch & Listen: administrator adds YouTube links or uploads short clips; public reads published clips.
CREATE TABLE IF NOT EXISTS public.video_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  video_url text NOT NULL,
  video_path text,
  thumbnail_url text,
  published boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.video_items ADD COLUMN IF NOT EXISTS video_path text;
ALTER TABLE public.video_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "TS public read published videos" ON public.video_items;
CREATE POLICY "TS public read published videos" ON public.video_items
  FOR SELECT TO anon, authenticated USING (published = true OR public.is_blog_admin());
DROP POLICY IF EXISTS "TS admin manage videos" ON public.video_items;
CREATE POLICY "TS admin manage videos" ON public.video_items
  FOR ALL TO authenticated USING (public.is_blog_admin()) WITH CHECK (public.is_blog_admin());
GRANT SELECT ON public.video_items TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.video_items TO authenticated;


-- Public playback; only the verified administrator can upload or delete clips.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('public-videos','public-videos',true,52428800,ARRAY['video/mp4','video/webm','video/quicktime'])
ON CONFLICT (id) DO UPDATE SET public=true,file_size_limit=52428800,allowed_mime_types=EXCLUDED.allowed_mime_types;
DROP POLICY IF EXISTS "TS public read video files" ON storage.objects;
CREATE POLICY "TS public read video files" ON storage.objects
  FOR SELECT TO anon, authenticated USING (bucket_id='public-videos');
DROP POLICY IF EXISTS "TS admin upload video files" ON storage.objects;
CREATE POLICY "TS admin upload video files" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id='public-videos' AND public.is_blog_admin() AND (storage.foldername(name))[1]=auth.uid()::text);
DROP POLICY IF EXISTS "TS admin delete video files" ON storage.objects;
CREATE POLICY "TS admin delete video files" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id='public-videos' AND public.is_blog_admin());
