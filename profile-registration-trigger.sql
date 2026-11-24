-- THOUGHTS & STORIES — MEMBER REGISTRATION + PROFILE RECORDS
-- Run once in Supabase SQL Editor. Safe to run again.
-- Passwords remain in Supabase Auth; this table stores member profile details only.

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
    split_part(NEW.email, '@', 1)
  );

  INSERT INTO public.profiles (id, email, username, display_name, role, created_at)
  VALUES (
    NEW.id,
    NEW.email,
    chosen_username,
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'display_name', ''), chosen_username),
    'reader',
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    username = COALESCE(NULLIF(public.profiles.username, ''), EXCLUDED.username),
    display_name = COALESCE(NULLIF(public.profiles.display_name, ''), EXCLUDED.display_name);
  -- Deliberately do not update role: an existing administrator stays administrator.
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_blog_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_blog_profile
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_blog_user();

-- Backfill email and username for existing profiles without changing their roles.
UPDATE public.profiles p
SET email = COALESCE(p.email, u.email),
    username = COALESCE(NULLIF(p.username, ''), NULLIF(u.raw_user_meta_data->>'username', ''), NULLIF(u.raw_user_meta_data->>'display_name', ''), split_part(u.email, '@', 1))
FROM auth.users u
WHERE p.id = u.id;
