-- THOUGHTS & STORIES — secure BookZone PDFs, M-Pesa purchases and member registry
-- Run this once in Supabase SQL Editor. Safe to run again; existing books/articles remain.
-- Requires the existing public.is_blog_admin() function.

-- 1) Add private PDF storage path to existing books.
ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS book_url text,
  ADD COLUMN IF NOT EXISTS access_type text NOT NULL DEFAULT 'free',
  ADD COLUMN IF NOT EXISTS price numeric(12,2),
  ADD COLUMN IF NOT EXISTS purchase_url text,
  ADD COLUMN IF NOT EXISTS pdf_path text;

-- Remove old direct PDF URLs from paid listings. Re-upload each paid title's PDF below
-- so the new private file is the only reading copy exposed by the website.
UPDATE public.books SET book_url = NULL, purchase_url = NULL WHERE access_type = 'purchase';

-- 2) Payment ledger. Only server functions using the Supabase service role may write here.
CREATE TABLE IF NOT EXISTS public.book_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  amount integer NOT NULL CHECK (amount > 0),
  currency text NOT NULL DEFAULT 'KES',
  phone text NOT NULL,
  payer_phone text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','failed')),
  checkout_request_id text,
  merchant_request_id text,
  mpesa_receipt text,
  verified_amount integer,
  failure_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS book_purchases_checkout_request_uidx
  ON public.book_purchases(checkout_request_id) WHERE checkout_request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS book_purchases_member_book_status_idx
  ON public.book_purchases(user_id, book_id, status);
ALTER TABLE public.book_purchases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Members read own book purchases" ON public.book_purchases;
DROP POLICY IF EXISTS "Admins read all book purchases" ON public.book_purchases;
CREATE POLICY "Members read own book purchases" ON public.book_purchases
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_blog_admin());
REVOKE INSERT, UPDATE, DELETE ON public.book_purchases FROM anon, authenticated;
GRANT SELECT ON public.book_purchases TO authenticated;

-- 3) Private PDF bucket. Do NOT change this bucket to public.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('paid-books', 'paid-books', false, 52428800, ARRAY['application/pdf'])
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 52428800,
  allowed_mime_types = ARRAY['application/pdf'];
DROP POLICY IF EXISTS "TS admin upload private book PDFs" ON storage.objects;
CREATE POLICY "TS admin upload private book PDFs" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'paid-books' AND public.is_blog_admin() AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "TS admin update private book PDFs" ON storage.objects;
CREATE POLICY "TS admin update private book PDFs" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'paid-books' AND public.is_blog_admin())
  WITH CHECK (bucket_id = 'paid-books' AND public.is_blog_admin());
DROP POLICY IF EXISTS "TS admin delete private book PDFs" ON storage.objects;
CREATE POLICY "TS admin delete private book PDFs" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'paid-books' AND public.is_blog_admin());
-- No client SELECT policy is created. Readers receive short-lived signed URLs only
-- after the server checks free access or a confirmed purchase.

-- 4) Ensure every newly registered Supabase Auth account gets a member profile.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS username text,
  ADD COLUMN IF NOT EXISTS display_name text,
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'reader',
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION public.handle_new_blog_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  chosen_username text;
BEGIN
  chosen_username := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'username', ''),
    NULLIF(NEW.raw_user_meta_data->>'display_name', ''),
    NULLIF(split_part(COALESCE(NEW.email, ''), '@', 1), ''),
    'reader-' || left(NEW.id::text, 8)
  );
  INSERT INTO public.profiles (id, email, username, display_name, role, created_at)
  VALUES (
    NEW.id,
    NEW.email,
    chosen_username,
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'display_name', ''), chosen_username),
    'reader',
    COALESCE(NEW.created_at, now())
  )
  ON CONFLICT (id) DO UPDATE SET
    email = COALESCE(EXCLUDED.email, public.profiles.email),
    username = COALESCE(NULLIF(public.profiles.username, ''), EXCLUDED.username),
    display_name = COALESCE(NULLIF(public.profiles.display_name, ''), EXCLUDED.display_name);
  -- Never change role here: existing administrators retain administrator access.
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created_blog_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_blog_profile
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_blog_user();

-- Backfill profiles for all existing Auth accounts; preserve existing role values.
INSERT INTO public.profiles (id, email, username, display_name, role, created_at)
SELECT
  u.id,
  u.email,
  COALESCE(NULLIF(u.raw_user_meta_data->>'username', ''), NULLIF(u.raw_user_meta_data->>'display_name', ''), NULLIF(split_part(COALESCE(u.email, ''), '@', 1), ''), 'reader-' || left(u.id::text, 8)),
  COALESCE(NULLIF(u.raw_user_meta_data->>'display_name', ''), NULLIF(u.raw_user_meta_data->>'username', ''), NULLIF(split_part(COALESCE(u.email, ''), '@', 1), ''), 'Reader'),
  'reader',
  COALESCE(u.created_at, now())
FROM auth.users u
ON CONFLICT (id) DO UPDATE SET
  email = COALESCE(public.profiles.email, EXCLUDED.email),
  username = COALESCE(NULLIF(public.profiles.username, ''), EXCLUDED.username),
  display_name = COALESCE(NULLIF(public.profiles.display_name, ''), EXCLUDED.display_name);

-- Profiles are listed in Admin Studio from public.profiles. Existing RLS should
-- continue to permit admins to read all rows via the existing is_blog_admin() policy.
