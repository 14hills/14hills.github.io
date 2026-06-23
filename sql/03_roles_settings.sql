-- ============================================================
-- ⛔ DEPRECATED / 미사용 — sql/04_access_control.sql 로 대체됨
--    (SaiZen ops 모델로 통일: profiles → user_access, role admin/manager/staff,
--     카드(areas) 기반 + 가입요청. 실행하지 마세요. 02 → 04 순서로 실행.)
--    이미 실행했다면: 04가 트리거를 덮어쓰며, 잔여 profiles 테이블은
--    drop table if exists profiles cascade; 로 정리 가능(선택).
-- ============================================================
-- (이하 구버전 — 참고용 보존)
-- ============================================================
-- 14hills Supabase — 역할(RBAC) · 설정값 · 활동로그 (Phase 2 기반)
-- 적용: SQL Editor → 붙여넣기 → Run  (sql/02 이후 실행)
-- 역할: master(마스터) / manager(관리담당) / operator(일반)
--  - 계정 생성은 Supabase 대시보드(Authentication → Users)
--  - 가입 시 profiles 자동 생성(기본 operator) → 마스터가 역할 부여
-- ============================================================

-- ── 프로필(역할) : auth.users 1:1 ──────────────────────────
create table if not exists profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text,
  role        text not null default 'operator'
                check (role in ('master','manager','operator')),
  active      boolean not null default true,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- 현재 로그인 사용자의 역할 (security definer로 RLS 재귀 회피)
create or replace function public.app_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;
create or replace function public.is_master() returns boolean
  language sql stable as $$ select public.app_role() = 'master'; $$;
create or replace function public.is_staff() returns boolean
  language sql stable as $$ select public.app_role() in ('master','manager'); $$;

-- 신규 auth 사용자 → profiles 자동 생성(기본 operator)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, role)
  values (new.id, new.email, 'operator')
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

drop trigger if exists trg_profiles_updated on profiles;
create trigger trg_profiles_updated before update on profiles
  for each row execute function set_updated_at();   -- set_updated_at()는 sql/02에서 생성됨

-- ── 설정값(요율·메뉴 등) key/value ─────────────────────────
create table if not exists app_settings (
  key         text primary key,             -- 예: rates.stay / rates.transport / rates.merit / menu.dinner ...
  value       jsonb not null,
  updated_by  uuid references auth.users(id),
  updated_at  timestamptz default now()
);

-- ── 활동 로그 ──────────────────────────────────────────────
create table if not exists activity_log (
  id         bigserial primary key,
  user_id    uuid references auth.users(id),
  email      text,
  action     text,                          -- login / save_session / update_setting / set_role ...
  detail     jsonb,
  created_at timestamptz default now()
);
create index if not exists idx_activity_created on activity_log(created_at desc);

-- ============================================================
-- RLS
-- ============================================================
alter table profiles     enable row level security;
alter table app_settings enable row level security;
alter table activity_log enable row level security;

-- profiles: 본인 행은 읽기 / 마스터는 전체 읽기·수정(역할 부여)
drop policy if exists profiles_select on profiles;
create policy profiles_select on profiles for select to authenticated
  using (id = auth.uid() or public.is_master());
drop policy if exists profiles_update on profiles;
create policy profiles_update on profiles for update to authenticated
  using (public.is_master()) with check (public.is_master());
drop policy if exists profiles_insert on profiles;
create policy profiles_insert on profiles for insert to authenticated
  with check (public.is_master());   -- 일반 가입은 트리거(security definer)가 처리

-- app_settings: 로그인 전체 읽기 / master·manager 쓰기
drop policy if exists settings_select on app_settings;
create policy settings_select on app_settings for select to authenticated using (true);
drop policy if exists settings_write on app_settings;
create policy settings_write on app_settings for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- activity_log: 로그인 누구나 insert / master·manager만 조회
drop policy if exists log_insert on activity_log;
create policy log_insert on activity_log for insert to authenticated with check (true);
drop policy if exists log_select on activity_log;
create policy log_select on activity_log for select to authenticated using (public.is_staff());

-- ============================================================
-- ★ 최초 마스터 지정 (대시보드에서 계정 만든 뒤, 본인 이메일로 1회 실행)
--   update public.profiles set role='master' where email='YOUR_EMAIL';
-- (트리거가 가입 시 자동 생성하므로, 먼저 로그인 1회 또는 Users에서 생성 후 실행)
-- ============================================================
