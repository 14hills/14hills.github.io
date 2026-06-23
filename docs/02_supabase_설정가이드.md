# 14hills Supabase 연동 설정 가이드 (Phase 1)

> 목표: `/app/`을 **로그인 인증 + Supabase 백엔드**로 운영(현 앱 유지 + 동기화).
> 이 단계에서 **프로젝트 생성 → 스키마 적용 → 로그인 설정 → 앱 연결**까지 끝냅니다.
> 데이터 저장/불러오기(동기화)는 Phase 2에서 연결합니다.

## 0. 준비물
- Supabase 계정(github.com 로그인 가능) — https://supabase.com
- 운영자 이메일/비밀번호(앱 로그인용)

## 1. 프로젝트 생성 (서울 리전 권장)
1. https://supabase.com/dashboard → **New project**
2. Name: `14hills-ops` (자유) · Database Password: 강력하게 설정(보관)
3. **Region: `Northeast Asia (Seoul)`** 선택 → Create
4. 1~2분 후 프로비저닝 완료

## 2. 스키마 + RLS 적용
1. 좌측 **SQL Editor** → **New query**
2. 저장소의 **`sql/02_supabase_schema.sql`** 내용을 전체 붙여넣기 → **Run**
3. `Success` 확인 (테이블 6개 + RLS 정책 + 트리거 생성)
   - groups · guests · arrangements · dinners · dinner_assignments · settlements

## 3. 로그인(Email) 활성화 + 운영자 계정
1. **Authentication → Providers → Email** : `Enable` (기본 활성)
   - 내부 도구면 **Confirm email** 끄면 즉시 로그인 편함(Auth → Providers → Email → Confirm email off)
2. **Authentication → Users → Add user → Create new user**
   - 이메일/비밀번호 입력 → 생성 (이 계정으로 앱에 로그인)

## 4. 접속 키 복사
1. **Settings (톱니) → API**
2. 복사해 둘 값 2가지:
   - **Project URL** : `https://xxxx.supabase.co`
   - **anon public** key (긴 JWT 문자열) — ⚠️ `service_role` 키는 **절대 프론트에 넣지 않음**

## 5. 앱에 연결
1. `https://14hills.github.io/app/` 접속
2. 우측 상단 **`☁ Supabase`** 버튼 → **연결 설정**
3. Project URL · anon key 붙여넣기 → **저장** (브라우저 localStorage `14h_sb_url`/`14h_sb_key`에 보관)
4. 새로고침하면 **로그인 화면**이 뜸 → 3단계에서 만든 계정으로 로그인
5. 로그인되면 운영 화면 사용 가능 (헤더에 로그인 이메일·로그아웃 표시)

> 미연결(키 미입력) 상태에서는 **기존처럼 엑셀 업로드+localStorage**로 그대로 동작합니다.
> 키를 넣은 순간부터 **로그인 게이트**가 활성화됩니다.

## 보안 메모
- 프론트에는 **anon 키만** 사용(공개돼도 RLS로 보호). `service_role`은 서버 전용.
- 현재 RLS는 *로그인 사용자 전체 접근*(내부 운영 전제). 사용자별 분리가 필요하면
  `groups.user_id` 등 소유자 컬럼 + 정책으로 확장(요청 시 적용).
- 비밀번호 분실 시 Supabase Authentication에서 재설정.

## 다음 (Phase 2 — 데이터 동기화)
- 현재 세션의 그룹·고객·수배·저녁·정산을 **Supabase에 저장 / 불러오기** 버튼 연결
- 월(ym) 세션 단위 업서트(중복 방지: `groups(ym,event_seq)` 유니크)
- 충돌/변경 감지(기존 스냅샷 로직과 연계)
