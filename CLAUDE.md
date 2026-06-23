# 14hills 운영 통합 시스템 — 킥오프 / 작업 규칙 (CLAUDE.md)

이 문서는 **새 대화에서 14hills 운영 앱을 시작**할 때 가장 먼저 읽는 문서다.
SaiZen 야마나미 시스템(`/app/index.html`)의 구조·코드 패턴을 차용해 **포틴힐즈(14hills) 전용 운영 도구**를 만든다.
모든 응답은 **한국어 존댓말(격식체)**. **코드가 항상 정답**이며, 문서가 코드와 어긋나면 코드를 신뢰한다.

> 함께 읽기: `14hills/docs/00_인계브리프.md`(원본 인계 브리프) · `14hills/sql/01_schema_draft.sql`(Supabase 스키마 초안).
> 상위 저장소 규칙: 루트 `/CLAUDE.md`(SaiZen 작업 규칙 — 검증·디자인·i18n 절차를 그대로 재사용).

---

## 1. 무엇을 / 누구를 위해
- **포틴힐즈 컨트리클럽(名古屋, 나고야) · 18홀 골프장**의 현장 운영 자동화 도구.
- 한국 골프투어 송객을 받아 **네임택·현지 수배서·저녁 명단·현지 정산** 산출물을 생성한다.
- 고객 소통은 한국어, 현장 산출물은 일본어 기조(SaiZen와 동일 철학).

## 2. 범위 — 복제할 4개 모듈 (항공커버 제외)
| 14hills 모듈 | SaiZen 대응 | `/app/index.html` 진입 함수(현재 기준) |
|---|---|---|
| ① 네임택 | 네임택 | `buildNametag()` · `downloadNametag()` · `generateAndPrintLabels()` |
| ② 현지 수배서 | 송영·숙박·골프 통합 | `collectDispatchData()` · `buildDispatch()` + 인쇄/엑셀 섹션 |
| ③ 저녁 명단표 | 저녁 | `buildDinner()` · `renderDinner()` · `_downloadDinner()` · `generateAndPrintRestaurants()` · `generateAndPrintDinnerOrder()` |
| ④ 현지 정산표 | 정산 | `buildSettle()` · `downloadSettle()` |

- 공통 인프라: 태그코드 `makeTagCode()` / `makeTagCodeSafe()` / `numToTeamCode4()` / `buildTagCodeMap()`, xlsx 헬퍼(`xlSave`/`xlHeader`/`xlDataRow`/`xlSection`/`xlColWidths`), 헤더 정의 `HDRS.*`.
- **항공커버(②탭)·송영 배차/숙박/골프 단독 탭은 가져오지 않는다.** 라운딩·카트·식사·송영은 **수배서 한 장**으로 통합한다(인계 브리프 §3·§4).

## 3. 14hills 특화 (SaiZen와 다른 점 — 교체할 상수)
- **27홀 리조트(야마나미) → 18홀 단일 골프장.** SaiZen의 코스 상수
  `YAMA_COURSES = ['ASO','SOBO','KUJU','']` / `YAMA_COURSE_LABELS`(`/app/index.html` 내 다수 위치)와
  `getGolfInfo()`/`getGolfDayType()`의 27홀·9홀서비스·구주고원/야마나미 분기를 **18홀 단일 코스 규칙으로 교체**한다.
- 숙박 4시설(야마나미/쿠주힐즈/간지/시즈노야도) 분기 → 14hills 실제 시설로 교체(숙박 비중 낮으면 수배서에 통합).
- **출발지 코드 ICN / PUS / TAE 그대로 사용**(SaiZen 표준화 로직 `origin` 재사용 가능).
- 통화 **JPY 기준**(정산 `currency default 'JPY'`).
- **태그코드 포맷 확정(§6.3)**: `숙박prefix-MMDD입국일-팀알파-개인번호`(예 `H-0702-A-01`). SaiZen `Y-0503-aa1` 양식 차용 — 숙박 prefix는 **H(호텔)/C(카라반)/X(미정)** 2유형. 구현은 `app/index.html`의 `buildTeams`/`buildGuests`/`accomCode`, 상세는 `docs/00_인계브리프.md §5-2`.

## 4. Supabase (14hills 전용 — SaiZen DB와 완전 분리)
- **🔑 키 명칭 변경(중요·기억)**: Supabase가 **`anon public key` → `Publishable key`**(`sb_publishable_…`), **`service_role` → `Secret key`**로 명칭을 바꿈. 프론트엔 **Publishable key**만 사용(구 anon과 동일 역할·공개 가능). 단 **RLS의 역할명 `anon`/`authenticated`는 그대로**(키 명칭과 별개).
- **별도 프로젝트**(리전: 활성 사용자=일본이면 도쿄, 한국이면 서울 — 내부도구라 차이 미미). **Publishable key(구 anon)만 프론트에**, `Secret key`(구 service_role) 노출 금지.
- 스키마 초안: `14hills/sql/01_schema_draft.sql` (`groups`·`guests`·`arrangements`·`dinners`·`dinner_assignments`·`settlements`).
- **RLS 필수**: anon 공개 접근 시 데이터 노출 위험 → 인증 방식 확정 후 policy 추가(스키마 말미 주의 참조).
- 접속정보 localStorage 키는 SaiZen `/ops/`(`saizen_sb_url`/`saizen_sb_key`)와 **충돌하지 않도록 14hills 전용 키**(`14h_sb_url`/`14h_sb_key` 등)로 분리.

## 5. 재사용할 SaiZen 규칙 (루트 `/CLAUDE.md` 참조)
- **디자인 토큰**: `/app/index.html` 상단 `:root`(약 22~37줄) — 액센트 올리브 `#647548` 등. 14hills 고유색을 쓸지 §6에서 결정.
- **검증(납품 전 필수)**: ① 인라인 `<script>` 추출 후 `node --check` ② jsdom 스모크 테스트(실/모의 데이터로 핵심 함수 실행·결과 검증). 절차·함정은 루트 `/CLAUDE.md` §4 그대로.
- **출력 규칙**: 다운로드 파일명은 영문(회사 PC 한글 차단), 셀 내용은 한·일 유지. 읽기=SheetJS, 쓰기=ExcelJS 4.3.0(CDN).
- **단일 HTML 바이브 코딩**(SaiZen `/app/` 방식) vs **다중 페이지+Supabase**(`/ops/` 방식) 중 어느 골격을 따를지 §6에서 결정.

## 6. 새 대화에서 **가장 먼저 결정할 사항** (열린 결정)
1. **배포 위치**: 같은 저장소 `saizenjp.github.io/14hills/`(현재 스테이징 위치) vs **신규 저장소**. → Pages 게시 경로·도메인에 영향.
2. **골격**: SaiZen `/app/` 패턴(단일 HTML + localStorage 출력)인가, `/ops/` 패턴(다중 페이지 + Supabase)인가, 혼합인가.
3. ~~태그코드 포맷 확정~~ ✅ **확정**: `숙박prefix-MMDD-팀알파-번호`(`H/C/X`-…). §3·`docs/00 §5-2` 참조.
4. **18홀 코스/라운딩 규칙 상수**: 포틴힐즈 실제 코스명·티오프·카트·식사 규칙 입력값 확보.
5. **입력 데이터 포맷**: 엠클릭 엑셀 2종을 그대로 쓰는가, 14hills 전용 입력 양식인가.
6. **디자인**: SaiZen 올리브 팔레트 재사용 vs 14hills 전용 브랜드 컬러.

## 7. 체크리스트 (인계 브리프 §6 기준)
- [ ] §6 열린 결정 6가지 확정
- [ ] 14hills Supabase 프로젝트 생성 + Project URL · Publishable key(구 anon) 확보
- [ ] `/app/index.html`에서 네임택 / 수배서 / 저녁 / 정산 로직 추출
- [ ] 14hills 상수로 분기(골프장명 · 18홀 · 출발지 · JPY)
- [ ] 초안 스키마 적용 후 구조에 맞게 확정 + RLS policy
- [ ] xlsx 출력 포맷 동일 적용
- [ ] `node --check` + jsdom 스모크 테스트 통과
- [ ] 배포 경로대로 게시

---
*작성 시점 기준: SaiZen `/app/index.html` v14.6. 함수명·줄 위치는 변동될 수 있으니 작업 전 실제 코드를 먼저 확인한다.*
