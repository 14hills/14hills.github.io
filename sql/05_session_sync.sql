-- ============================================================================
--  14hills — 세션 스냅샷 동기화 (여러 PC·담당자 간 같은 데이터 공유)
--  (sql/02 → 04 실행 후 마지막에 실행. 멱등 — 반복 실행 안전)
-- ----------------------------------------------------------------------------
--  앱은 「월(YYYY-MM) 세션」 단위로 동작하며, 한 세션의 전체 작업 상태
--  (원본 분석 processed·개인 passengers·수기입력 manualData·차감 deductions)를
--  JSONB 스냅샷 1행으로 저장한다. 동료는 엑셀 재업로드 없이 그대로 불러온다.
--
--  · 저장/불러오기 = ym(월) 단위 upsert·select. last-write-wins(나중 저장이 덮음).
--  · 내부 운영 도구 전제 → 로그인(authenticated) 사용자 전체 접근(anon 차단).
--    카드 단위로 더 좁히려면 정책을 has_area('data') 등으로 교체 가능.
-- ============================================================================
create table if not exists sessions (
  ym            text primary key,              -- 'YYYY-MM' (세션 키)
  data          jsonb not null,                -- {v, processed[], passengers[], manualData{}, deductions[]}
  groups        int,                           -- 요약: 숙박 그룹(팀) 수
  pax           int,                           -- 요약: 총 인원
  updated_email text,                          -- 마지막 저장자 이메일
  updated_by    uuid references auth.users(id) default auth.uid(),
  updated_at    timestamptz not null default now()
);

alter table sessions enable row level security;
drop policy if exists sessions_all on sessions;
create policy sessions_all on sessions
  for all to authenticated using (true) with check (true);

create index if not exists idx_sessions_updated on sessions(updated_at desc);

-- ============================================================================
--  적용 후: /app/ 세션 바의 [☁ 저장] / [☁ 불러오기] 버튼으로 동작.
--  활동 로그에는 cloud_save / cloud_load 로 기록된다(sql/04 activity_log).
-- ============================================================================
