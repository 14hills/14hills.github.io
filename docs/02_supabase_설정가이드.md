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
   - **Publishable key** (구 `anon public key`, 형식 `sb_publishable_…` 또는 레거시 JWT `eyJ…`) — ⚠️ `Secret key`(구 `service_role`)는 **절대 프론트에 넣지 않음**

## 5. 앱에 연결
1. `https://14hills.github.io/app/` 접속
2. 우측 상단 **`☁ Supabase`** 버튼 → **연결 설정**
3. Project URL · Publishable key 붙여넣기 → **저장** (브라우저 localStorage `14h_sb_url`/`14h_sb_key`에 보관)
4. 새로고침하면 **로그인 화면**이 뜸 → 3단계에서 만든 계정으로 로그인
5. 로그인되면 운영 화면 사용 가능 (헤더에 로그인 이메일·로그아웃 표시)

> 미연결(키 미입력) 상태에서는 **기존처럼 엑셀 업로드+localStorage**로 그대로 동작합니다.
> 키를 넣은 순간부터 **로그인 게이트**가 활성화됩니다.

## 6. 역할(RBAC) 적용 — 마스터/관리담당/일반
1. **SQL Editor**에서 **`sql/03_roles_settings.sql`** 실행 (profiles·설정값·활동로그 + RLS)
2. 3단계에서 만든 운영자 계정으로 **앱에 한 번 로그인**(또는 Users에서 생성) → `profiles`에 자동 행 생성(기본 `operator`)
3. **본인을 마스터로 지정** (SQL Editor에서 1회):
   ```sql
   update public.profiles set role='master' where email='YOUR_EMAIL';
   ```
4. 이후 **마스터가 `/admin/`(마스터 페이지)에서** 다른 운영자의 역할(`manager`/`operator`)을 부여
   - **master**: 전체(운영·역할관리·세션데이터·설정값·로그)
   - **manager(관리담당)**: 운영·세션데이터·설정값·로그(보기)
   - **operator(일반)**: `/app/` 운영 기능만

## 보안 메모
- 프론트에는 **Publishable key(구 anon)만** 사용(공개돼도 RLS로 보호). `Secret key`(구 service_role)는 서버 전용.
- ℹ️ Supabase가 키 명칭을 바꿈: `anon` → **Publishable key**, `service_role` → **Secret key**. (RLS의 역할명 `anon`/`authenticated`는 그대로)
- **연결정보는 코드에 내장** 예정(Publishable key는 공개 가능) → 사용자는 **설정 없이 로그인만**. (Phase 2 적용 시 현 연결설정 패널은 마스터 전용/제거)
- 비밀번호 분실 시 Supabase Authentication에서 재설정.

## 7. 세션 데이터 동기화 (여러 PC·담당자 공유)
1. **SQL Editor**에서 **`sql/05_session_sync.sql`** 실행 (`sessions` 테이블 + RLS). *(sql/02 → 04 → 05 순서)*
2. `/app/` 상단 **세션 바**의 버튼으로 동작:
   - **`☁ 저장`** — 현재 월 세션(원본 분석·개인·수기입력·차감)을 클라우드에 통째로 저장(upsert).
   - **`☁ 불러오기`** — 저장된 세션 목록에서 선택 → **엑셀 재업로드 없이** 그 화면 그대로 복원.
3. 같은 `ym`(월)은 **나중 저장이 덮어씁니다**(last-write-wins). 저장/불러오기는 **활동 로그**(`cloud_save`/`cloud_load`)에 기록됩니다.
4. 동료가 보려면: 한 명이 `☁ 저장` → 다른 PC에서 로그인 후 `☁ 불러오기`.

> 미연결(키 미입력) 상태에서도 기존처럼 **엑셀 업로드+localStorage** 단독 사용은 그대로 가능합니다(클라우드 버튼만 안내 토스트).

## 다음 (Phase 2 — 멀티페이지 + 동기화)
- `/assets/sb.js`(연결 내장·인증·역할) → `/app/`(로그인 전용) · `/admin/`(마스터 페이지) ✅
- 세션(ym) **저장/불러오기**(`sql/05` · 세션 바 ☁ 버튼) ✅ — 정규화(그룹·고객·수배·…) 분리 저장은 추후
- 설정값(요율·메뉴)·활동로그를 마스터 페이지에서 관리 (활동로그 ✅)
