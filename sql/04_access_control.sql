-- ============================================================================
--  14hills — 접근 권한(RBAC) : 역할 3단계 + 카드별 권한 + 가입요청
--  (SaiZen ops 18/25/28 포팅 → 14hills 카드로 적응. 멱등. sql/02 이후 실행)
--  ★ sql/03_roles_settings.sql 은 이 파일로 대체됨 — 03 대신 02 → 04 실행.
-- ----------------------------------------------------------------------------
--  역할:  admin(마스터)   = 전 카드 + 권한관리(남의 권한 지정)
--         manager(관리담당)= 전 카드 접근(통괄), 권한관리 불가
--         staff(일반)      = areas 에 지정된 카드만 (기본값: 권한 없음)
--  카드(area) 키 ↔ /app/ 모듈:
--         data(데이터등록·업로드) · dispatch(現地手配書) · nametag(ネームタグ)
--         dinner(夕食名前版)       · settle(現地精算表)
--  · 새 계정 = 기본 staff + areas 비어있음(deny by default).
--  · 계정 발급은 Supabase 대시보드(자가가입 OFF). access_requests = '요청'일 뿐 계정 아님.
--  ⚠ 맨 아래 "마스터 지정"을 본인 이메일로 1회 실행.
-- ============================================================================

-- ── 사용자 권한/프로필 ──────────────────────────────────────
create table if not exists user_access (
  user_id    uuid        primary key references auth.users(id) on delete cascade,
  role       text        not null default 'staff' check (role in ('admin','manager','staff')),
  areas      text[]      not null default '{}',
  name       text,
  dept       text,
  title      text,
  updated_at timestamptz not null default now()
);
alter table user_access enable row level security;

-- 본인 행만 읽기(자기 권한 확인). 수정은 admin RPC로만.
drop policy if exists ua_self_read on user_access;
create policy ua_self_read on user_access
  for select to authenticated using (user_id = auth.uid());

-- 신규 가입자 자동 행 생성(기본 staff·권한없음) + 이름 메타 반영
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into user_access(user_id, name)
  values (new.id, new.raw_user_meta_data->>'name')
  on conflict (user_id) do nothing;
  return new;
end $$;
drop trigger if exists trg_new_user on auth.users;
drop trigger if exists on_auth_user_created on auth.users;   -- sql/03 트리거 제거(대체)
create trigger trg_new_user after insert on auth.users
  for each row execute function handle_new_user();

-- 기존 사용자 백필
insert into user_access(user_id, name)
select id, raw_user_meta_data->>'name' from auth.users
on conflict (user_id) do nothing;

-- ── 판정 함수 ───────────────────────────────────────────────
create or replace function is_admin()
returns boolean language sql security definer set search_path = public stable as $$
  select exists(select 1 from user_access where user_id = auth.uid() and role = 'admin');
$$;
grant execute on function is_admin() to authenticated;

create or replace function is_staff_up()    -- admin 또는 manager
returns boolean language sql security definer set search_path = public stable as $$
  select exists(select 1 from user_access where user_id = auth.uid() and role in ('admin','manager'));
$$;
grant execute on function is_staff_up() to authenticated;

-- UI 게이트용: admin/manager 는 전 카드, staff 는 지정 카드만
create or replace function has_area(p_area text)
returns boolean language sql security definer set search_path = public stable as $$
  select exists(
    select 1 from user_access
    where user_id = auth.uid()
      and (role in ('admin','manager') or p_area = any(areas))
  );
$$;
grant execute on function has_area(text) to authenticated;

-- 데이터테이블 RLS 2단계용(여러 카드 중 하나라도; admin 무조건)
create or replace function has_any_area(p_areas text[])
returns boolean language sql security definer set search_path = public stable as $$
  select exists(
    select 1 from user_access
    where user_id = auth.uid()
      and (role = 'admin' or areas && p_areas)
  );
$$;
grant execute on function has_any_area(text[]) to authenticated;

-- ── 내 권한·프로필 조회(클라이언트) ─────────────────────────
drop function if exists me_access();
create function me_access()
returns table(role text, areas text[], name text, dept text, title text)
language plpgsql security definer set search_path = public stable as $$
begin
  return query
    select ua.role, ua.areas,
           coalesce(ua.name, (select raw_user_meta_data->>'name' from auth.users where id=auth.uid())),
           ua.dept, ua.title
    from user_access ua where ua.user_id = auth.uid();
  if not found then
    return query select 'staff'::text, '{}'::text[], null::text, null::text, null::text;
  end if;
end $$;
grant execute on function me_access() to authenticated;

-- ── 관리자: 전체 사용자 목록 ────────────────────────────────
drop function if exists admin_list_users();
create function admin_list_users()
returns table(user_id uuid, email text, name text, role text, areas text[], dept text, title text)
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception '권한 없음(관리자 전용)'; end if;
  return query
    select ua.user_id, u.email::text,
           coalesce(ua.name, u.raw_user_meta_data->>'name') as name,
           ua.role, ua.areas, ua.dept, ua.title
    from user_access ua join auth.users u on u.id = ua.user_id
    order by case ua.role when 'admin' then 0 when 'manager' then 1 else 2 end, u.email;
end $$;
grant execute on function admin_list_users() to authenticated;

-- ── 관리자: 권한 지정(이름·부서·직급 포함) ──────────────────
drop function if exists admin_set_access(uuid, text, text[]);
drop function if exists admin_set_access(uuid, text, text[], text, text, text);
create function admin_set_access(p_user uuid, p_role text, p_areas text[],
                                 p_name text default null, p_dept text default null, p_title text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception '권한 없음(관리자 전용)'; end if;
  if p_role not in ('admin','manager','staff') then raise exception '잘못된 role'; end if;
  update user_access
     set role=p_role, areas=coalesce(p_areas,'{}'),
         name=nullif(p_name,''), dept=nullif(p_dept,''), title=nullif(p_title,''),
         updated_at=now()
   where user_id=p_user;
end $$;
grant execute on function admin_set_access(uuid, text, text[], text, text, text) to authenticated;

-- ============================================================================
--  가입(계정 발급) 요청 — 미로그인자가 로그인 화면에서 보냄(요청일 뿐, 계정 아님)
-- ============================================================================
create table if not exists access_requests (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  email       text not null,
  dept        text,
  message     text,
  status      text not null default 'pending',   -- pending / approved / rejected
  created_at  timestamptz not null default now(),
  handled_by  text,
  handled_at  timestamptz
);
create index if not exists idx_access_requests_status on access_requests(status, created_at desc);

grant insert on access_requests to anon, authenticated;
grant select, update, delete on access_requests to authenticated;
alter table access_requests enable row level security;

drop policy if exists ar_insert_any on access_requests;
create policy ar_insert_any on access_requests for insert to anon, authenticated with check (true);
drop policy if exists ar_read_staff on access_requests;
create policy ar_read_staff on access_requests for select to authenticated using (is_staff_up());
drop policy if exists ar_update_staff on access_requests;
create policy ar_update_staff on access_requests for update to authenticated using (is_staff_up()) with check (is_staff_up());
drop policy if exists ar_delete_admin on access_requests;
create policy ar_delete_admin on access_requests for delete to authenticated using (is_admin());

-- ============================================================================
--  설정값(요율·메뉴) · 활동 로그  (user_access 기반 정책)
-- ============================================================================
create table if not exists app_settings (
  key text primary key, value jsonb not null,
  updated_by uuid references auth.users(id), updated_at timestamptz default now()
);
alter table app_settings enable row level security;
drop policy if exists settings_select on app_settings;
create policy settings_select on app_settings for select to authenticated using (true);
drop policy if exists settings_write on app_settings;
create policy settings_write on app_settings for all to authenticated using (is_staff_up()) with check (is_staff_up());

create table if not exists activity_log (
  id bigserial primary key, user_id uuid references auth.users(id), email text,
  action text, detail jsonb, created_at timestamptz default now()
);
create index if not exists idx_activity_created on activity_log(created_at desc);
alter table activity_log enable row level security;
drop policy if exists log_insert on activity_log;
create policy log_insert on activity_log for insert to authenticated with check (true);
drop policy if exists log_select on activity_log;
create policy log_select on activity_log for select to authenticated using (is_staff_up());

-- ============================================================================
--  ⚠ 마스터 지정 — 아래 이메일을 본인 로그인 이메일로 바꿔 1회 실행
--    (대시보드 Authentication→Users 로 계정 생성 후, 또는 첫 로그인 후)
-- ----------------------------------------------------------------------------
--  update user_access set role='admin', updated_at=now()
--    where user_id = (select id from auth.users where email='YOUR_EMAIL');
-- ============================================================================
