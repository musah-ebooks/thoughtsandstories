-- Thoughts & Stories photo gallery setup.
-- Run this additional script ONCE in Supabase SQL Editor after the earlier upgrade.sql.
-- It creates a public-read image bucket; only verified administrators can upload or delete images.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('public-gallery', 'public-gallery', true, 10485760, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = true, file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

create table if not exists public.gallery_items (
  id uuid primary key default gen_random_uuid(),
  caption text not null default '',
  object_path text not null unique,
  published boolean not null default true,
  uploaded_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.gallery_items enable row level security;

drop policy if exists "Public can view published gallery items" on public.gallery_items;
create policy "Public can view published gallery items" on public.gallery_items
  for select to anon, authenticated using (published = true or public.is_blog_admin());
drop policy if exists "Admins add gallery items" on public.gallery_items;
create policy "Admins add gallery items" on public.gallery_items
  for insert to authenticated with check (public.is_blog_admin() and uploaded_by = auth.uid());
drop policy if exists "Admins update gallery items" on public.gallery_items;
create policy "Admins update gallery items" on public.gallery_items
  for update to authenticated using (public.is_blog_admin()) with check (public.is_blog_admin());
drop policy if exists "Admins delete gallery items" on public.gallery_items;
create policy "Admins delete gallery items" on public.gallery_items
  for delete to authenticated using (public.is_blog_admin());
grant select on public.gallery_items to anon, authenticated;
grant insert, update, delete on public.gallery_items to authenticated;

-- Public can fetch images because the bucket is public. Upload and delete remain admin-only.
drop policy if exists "Public read gallery images" on storage.objects;
create policy "Public read gallery images" on storage.objects
  for select to anon, authenticated using (bucket_id = 'public-gallery');
drop policy if exists "Admins upload gallery images" on storage.objects;
create policy "Admins upload gallery images" on storage.objects
  for insert to authenticated with check (bucket_id = 'public-gallery' and public.is_blog_admin() and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Admins delete gallery images" on storage.objects;
create policy "Admins delete gallery images" on storage.objects
  for delete to authenticated using (bucket_id = 'public-gallery' and public.is_blog_admin());
