-- 모여 커뮤니티 Supabase 초기 설정
-- Supabase Dashboard > SQL Editor에서 전체 실행하세요.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default '새 회원' check (char_length(nickname) between 1 and 24),
  role text not null default 'user' check (role in ('user','admin')),
  created_at timestamptz not null default now()
);
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  body text not null check (char_length(body) between 1 and 15000),
  category text not null default '자유' check (category in ('자유','질문','정보','유머','일상')),
  image_url text,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  parent_id uuid references public.comments(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 3000),
  is_hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(post_id,user_id)
);
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 1000),
  status text not null default 'open' check (status in ('open','reviewed','dismissed')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id,nickname)
  values(new.id, coalesce(nullif(left(new.raw_user_meta_data->>'nickname',24),''), '새 회원'));
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists(select 1 from public.profiles where id = (select auth.uid()) and role='admin'); $$;

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.likes enable row level security;
alter table public.reports enable row level security;

drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select using (true);
drop policy if exists "profile self update" on public.profiles;
create policy "profile self update" on public.profiles for update to authenticated
using (id=(select auth.uid())) with check (id=(select auth.uid()));

-- 일반 사용자가 profiles.role을 직접 바꾸지 못하도록 DB 트리거로 차단합니다.
create or replace function public.prevent_role_escalation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.role is distinct from old.role
     and not exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin') then
    raise exception 'Changing role requires administrator privileges';
  end if;
  return new;
end; $$;
drop trigger if exists protect_profile_role on public.profiles;
create trigger protect_profile_role before update on public.profiles
for each row execute function public.prevent_role_escalation();
-- 관리자 역할은 Dashboard SQL Editor에서만 부여하세요.
drop policy if exists "posts visible" on public.posts;
create policy "posts visible" on public.posts for select using (is_hidden=false or public.is_admin());
drop policy if exists "post insert own" on public.posts;
create policy "post insert own" on public.posts for insert to authenticated with check (user_id=(select auth.uid()));
drop policy if exists "post update own or admin" on public.posts;
create policy "post update own or admin" on public.posts for update to authenticated using (user_id=(select auth.uid()) or public.is_admin()) with check (user_id=(select auth.uid()) or public.is_admin());
drop policy if exists "post delete own or admin" on public.posts;
create policy "post delete own or admin" on public.posts for delete to authenticated using (user_id=(select auth.uid()) or public.is_admin());

drop policy if exists "comments visible" on public.comments;
create policy "comments visible" on public.comments for select using (is_hidden=false or public.is_admin());
drop policy if exists "comment insert own" on public.comments;
create policy "comment insert own" on public.comments for insert to authenticated with check (user_id=(select auth.uid()));
drop policy if exists "comment delete own or admin" on public.comments;
create policy "comment delete own or admin" on public.comments for delete to authenticated using (user_id=(select auth.uid()) or public.is_admin());

drop policy if exists "likes readable" on public.likes;
create policy "likes readable" on public.likes for select using (true);
drop policy if exists "like own insert" on public.likes;
create policy "like own insert" on public.likes for insert to authenticated with check (user_id=(select auth.uid()));
drop policy if exists "like own delete" on public.likes;
create policy "like own delete" on public.likes for delete to authenticated using (user_id=(select auth.uid()));

drop policy if exists "report own insert" on public.reports;
create policy "report own insert" on public.reports for insert to authenticated with check (reporter_id=(select auth.uid()));
drop policy if exists "report reporter or admin read" on public.reports;
create policy "report reporter or admin read" on public.reports for select to authenticated using (reporter_id=(select auth.uid()) or public.is_admin());
drop policy if exists "admin manage reports" on public.reports;
create policy "admin manage reports" on public.reports for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- 이미지 저장 버킷(공개 URL 방식). 업로드 경로의 첫 폴더는 로그인 사용자 UUID여야 합니다.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('post-images','post-images',true,5242880,array['image/png','image/jpeg','image/webp','image/gif'])
on conflict (id) do nothing;

drop policy if exists "images public read" on storage.objects;
create policy "images public read" on storage.objects for select using (bucket_id='post-images');
drop policy if exists "images owner upload" on storage.objects;
create policy "images owner upload" on storage.objects for insert to authenticated
with check (bucket_id='post-images' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "images owner delete" on storage.objects;
create policy "images owner delete" on storage.objects for delete to authenticated
using (bucket_id='post-images' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- 관리자 계정을 만든 뒤, 아래 쿼리에서 이메일을 실제 계정 이메일로 바꾸고 별도로 실행하세요.
-- update public.profiles p set role='admin'
-- from auth.users u where p.id=u.id and u.email='YOUR_ADMIN_EMAIL';
