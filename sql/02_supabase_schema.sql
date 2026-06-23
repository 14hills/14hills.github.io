-- ============================================================
-- 14hills 전용 Supabase — 확정 스키마 v1 (로그인 인증 + RLS)
-- 적용: Supabase 대시보드 → SQL Editor → 이 파일 전체 붙여넣기 → Run
-- 인증: Supabase Auth(이메일/비밀번호) 로그인 사용자만 접근 (anon 차단)
-- 통화 기본 JPY · 태그코드 = 비즈니스 키(예: H-0728-A-01), id(PK)와 분리
-- (sql/01_schema_draft.sql 초안을 앱 데이터 모델에 맞춰 확장·확정)
-- ============================================================

-- ── 그룹(행사/팀) : 앱 processed 1행 = 1그룹 ─────────────────
create table if not exists groups (
  id           uuid primary key default gen_random_uuid(),
  tag_code     text,                         -- 그룹 태그코드 prefix (H/C/X-MMDD-팀)
  event_no     text,                         -- 엠클릭 행사번호
  event_seq    text,                         -- 세션 내 행사 시퀀스 키
  rep_name     text,                         -- 대표고객
  team_name    text,                         -- 현장 팀명
  origin       text,                         -- ICN / PUS / TAE / CJJ
  depart_date  date,                         -- 출발일
  arrive_date  date,                         -- 도착(귀국)일
  nights       int,                          -- 박수
  pax          int,                          -- 인원
  accom        text,                         -- 호텔(WINDSOR) / 카라반(CARAVAN)
  room_type    text,                         -- 트윈 / 패밀리룸 / 스위트 / 카라반
  member_type  text,                         -- 회원권 구분
  status       text,                         -- 확정 / 대기 등
  product_name text,                         -- 상품명 원문
  remark       text,                         -- 비고(소스)
  local_remark text,                         -- 현지 비고(소스)
  ym           text,                         -- 세션 월(YYYY-MM)
  notes        text,                         -- 운영 메모(수기)
  created_at   timestamptz default now(),
  updated_at   timestamptz default now(),
  unique (ym, event_seq)
);

-- ── 참가자(고객) ───────────────────────────────────────────
create table if not exists guests (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid references groups(id) on delete cascade,
  tag_code    text,                         -- 개인 태그코드 (…-01)
  name_ko     text,                         -- 한글명 (네임택)
  name_en_sur text,                         -- 영문 성
  name_en_giv text,                         -- 영문 이름
  gender      text,                         -- M/F
  bday        text,                         -- 생년월일
  passport    text,
  phone       text,
  is_rep      boolean default false,
  notes       text,
  created_at  timestamptz default now()
);

-- ── 현지 수배서 (라운딩/카트/식사/송영 등 벤더 전달용) ───────
create table if not exists arrangements (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid references groups(id) on delete cascade,
  service_date date,
  item         text,                       -- 라운딩 / 9H추가 / 중식 / 석식 / 송영 …
  vendor       text,                       -- 현지 벤더/거래처
  qty          int,
  unit_price   numeric,
  currency     text default 'JPY',
  notes        text,
  created_at   timestamptz default now()
);

-- ── 저녁 명단표 ─────────────────────────────────────────────
create table if not exists dinners (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid references groups(id) on delete cascade,
  dinner_date date,
  table_no    text,                         -- 테이블 번호
  menu        text,                         -- 요일별 메뉴 등
  notes       text,
  created_at  timestamptz default now()
);

create table if not exists dinner_assignments (
  id        uuid primary key default gen_random_uuid(),
  dinner_id uuid references dinners(id) on delete cascade,
  guest_id  uuid references guests(id) on delete cascade,
  seat      text,
  notes     text
);

-- ── 현지 정산표 (JPY) ───────────────────────────────────────
create table if not exists settlements (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid references groups(id) on delete cascade,
  settle_date date,
  category    text,                         -- 숙박비 / 송영비 / 라운딩 / 추가 …
  description text,
  amount      numeric,
  currency    text default 'JPY',
  created_at  timestamptz default now()
);

-- ── 조회 성능 인덱스 ────────────────────────────────────────
create index if not exists idx_groups_ym         on groups(ym);
create index if not exists idx_guests_group       on guests(group_id);
create index if not exists idx_arrangements_group on arrangements(group_id, service_date);
create index if not exists idx_dinners_group      on dinners(group_id, dinner_date);
create index if not exists idx_dinner_assign      on dinner_assignments(dinner_id);
create index if not exists idx_settlements_group  on settlements(group_id, settle_date);

-- ============================================================
-- RLS (필수) — 로그인(authenticated) 사용자만 전체 접근, anon 차단
-- 내부 운영 도구 전제. 더 세분화하려면 user_id 컬럼 + owner 정책으로 확장.
-- ============================================================
alter table groups             enable row level security;
alter table guests             enable row level security;
alter table arrangements       enable row level security;
alter table dinners            enable row level security;
alter table dinner_assignments enable row level security;
alter table settlements        enable row level security;

-- 헬퍼: 각 테이블에 authenticated 전체 접근 정책
do $$
declare t text;
begin
  foreach t in array array['groups','guests','arrangements','dinners','dinner_assignments','settlements']
  loop
    execute format('drop policy if exists "auth_all" on %I;', t);
    execute format(
      'create policy "auth_all" on %I for all to authenticated using (true) with check (true);', t);
  end loop;
end $$;

-- updated_at 자동 갱신(groups)
create or replace function set_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end; $$ language plpgsql;
drop trigger if exists trg_groups_updated on groups;
create trigger trg_groups_updated before update on groups
  for each row execute function set_updated_at();

-- ============================================================
-- 적용 후: Authentication → Providers → Email 활성화,
--          Authentication → Users → 운영자 계정 추가(Invite/Create).
--          Project URL · anon public key 는 Settings → API 에서 복사.
-- ============================================================
