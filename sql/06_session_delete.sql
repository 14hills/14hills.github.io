-- ============================================================================
--  14hills — 클라우드 세션 삭제 권한 (sql/05_session_sync.sql 이후 실행 · 멱등)
-- ----------------------------------------------------------------------------
--  /app/ 의 [☁ 불러오기] 화면에 있는 🗑 버튼은 sessions 테이블의 해당 월(ym)
--  행을 DELETE 한다. 삭제하면 다른 PC에서도 사라진다(공유 데이터).
--
--  ✅ 이미 동작함 — 별도 실행이 꼭 필요한 건 아니다:
--     sql/05 의 정책
--        create policy sessions_all on sessions
--          for all to authenticated using (true) with check (true);
--     에서 `for all` 은 SELECT · INSERT · UPDATE · **DELETE** 를 모두 포함한다.
--     → 로그인(authenticated) 상태이면 추가 SQL 없이 삭제가 된다.
--
--  이 파일의 용도:
--     (1) 그 권한을 재확인(멱등 재생성) — 안심용. 그냥 실행해도 안전.
--     (2) [옵션] "삭제는 관리자만" 으로 좁혀 일반 담당자의 실수 삭제를 막는다.
-- ============================================================================


-- (1) 기본 — 모든 로그인 사용자 전체 접근(삭제 포함). 이미 있으면 동일하게 재생성.
alter table sessions enable row level security;
drop policy if exists sessions_all on sessions;
create policy sessions_all on sessions
  for all to authenticated using (true) with check (true);


-- ============================================================================
-- (2) [옵션] 삭제는 관리자(admin)만 — 공유 세션의 실수 삭제 방지
-- ----------------------------------------------------------------------------
--  읽기·저장·수정은 모든 로그인 사용자에게 두고, DELETE 만 is_admin() 으로 제한.
--  쓰려면 아래 블록의 주석(--)을 모두 풀고 실행한다.
--  (admin 또는 manager 까지 허용하려면 is_admin() → is_staff_up() 으로 교체)
-- ----------------------------------------------------------------------------
-- drop policy if exists sessions_all    on sessions;
-- drop policy if exists sessions_select on sessions;
-- drop policy if exists sessions_insert on sessions;
-- drop policy if exists sessions_update on sessions;
-- drop policy if exists sessions_delete on sessions;
--
-- create policy sessions_select on sessions
--   for select to authenticated using (true);
-- create policy sessions_insert on sessions
--   for insert to authenticated with check (true);
-- create policy sessions_update on sessions
--   for update to authenticated using (true) with check (true);
-- create policy sessions_delete on sessions
--   for delete to authenticated using (public.is_admin());
-- ============================================================================
--  적용 후 확인: Supabase 대시보드 → Database → Policies → sessions 에서
--  정책 목록을 볼 수 있다. 삭제 동작은 활동 로그(activity_log)에 cloud_delete 로
--  기록된다(sql/04).
-- ============================================================================
