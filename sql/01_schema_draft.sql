-- ============================================================
-- 14hills 전용 Supabase — 초안 스키마 (네임택 / 수배서 / 저녁 / 정산)
-- SaiZen 프로젝트에서 v13 구조에 맞춰 확정하세요.
-- 태그코드 = 비즈니스 키 (예: 6-0312-A-01), id(PK)와 분리 운용.
-- ============================================================

-- 그룹(팀) ---------------------------------------------------
create table groups (
  id          uuid primary key default gen_random_uuid(),
  tag_code    text unique not null,        -- Y-MMDD-팀알파-번호
  name        text,                        -- 그룹/팀명
  depart_date date,                        -- 출발일
  departure   text,                        -- ICN / PUS / TAE
  notes       text,
  created_at  timestamptz default now()
);

-- 참가자(고객) -----------------------------------------------
create table guests (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid references groups(id) on delete cascade,
  tag_code    text,                        -- 개인 태그코드
  name_ko     text,                        -- 한글명 (네임택)
  name_en     text,                        -- 영문명
  gender      text,
  notes       text,
  created_at  timestamptz default now()
);

-- 현지 수배서 (라운딩/카트/식사/송영 등 벤더 전달용) ---------
create table arrangements (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid references groups(id) on delete cascade,
  service_date date,
  item         text,                       -- 라운딩 / 카트 / 중식 / 송영 ...
  vendor       text,                       -- 현지 벤더/거래처
  qty          int,
  unit_price   numeric,
  currency     text default 'JPY',
  notes        text
);

-- 저녁 명단표 -------------------------------------------------
create table dinners (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid references groups(id) on delete cascade,
  dinner_date date,
  venue       text,                        -- 식당명
  menu        text,
  notes       text
);

create table dinner_assignments (
  id        uuid primary key default gen_random_uuid(),
  dinner_id uuid references dinners(id) on delete cascade,
  guest_id  uuid references guests(id) on delete cascade,
  seat      text,                          -- 테이블/좌석 메모
  notes     text
);

-- 현지 정산표 -------------------------------------------------
create table settlements (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid references groups(id) on delete cascade,
  settle_date date,
  category    text,                        -- 라운딩비 / 식대 / 카트 / 기타
  description text,
  amount      numeric,
  currency    text default 'JPY',
  created_at  timestamptz default now()
);

-- 조회 성능용 인덱스 -----------------------------------------
create index on guests(group_id);
create index on arrangements(group_id, service_date);
create index on dinners(group_id, dinner_date);
create index on dinner_assignments(dinner_id);
create index on settlements(group_id, settle_date);

-- ============================================================
-- RLS(행 수준 보안) 주의:
--   운영자만 쓰는 내부 도구라면 RLS를 켜고 인증 정책을 명확히 설정.
--   anon 키로 공개 접근 시 데이터 노출 위험 → 정책 없이 운영 금지.
--   (SaiZen 프로젝트에서 인증 방식 확정 후 policy 추가)
-- ============================================================
