# Contributing — Little Signals (2026 Capstone 18)

본 저장소는 국민대 2026 캡스톤 18조의 작업 공간입니다. 외부 기여자는 이슈로 시작해 주시고, 팀원은 아래 워크플로우를 따릅니다.

## 핵심 규칙

1. **`master`에 직접 푸시 금지.** 모든 변경은 PR 리뷰를 거쳐야 합니다.
2. **브랜치는 의도가 드러나는 prefix로.** `docs/`, `feat/`, `fix/`, `chore/`, `refactor/`, `test/`, `infra/` 중 하나로 시작합니다. 예: `feat/cycle-history-api`, `fix/wear-os-permission-leak`.
3. **하나의 PR은 하나의 의도.** 리팩터링과 기능 추가를 섞지 마세요. 커밋이 많은 것보다 PR이 작은 게 중요합니다.
4. **머지 전에 CI 통과.** GitHub Actions가 빨갛게 뜬 PR은 머지하지 않습니다.
5. **시크릿/자격증명 커밋 금지.** `.env`, AWS 키, Firebase 서비스 계정 JSON, Supabase service-role 키는 절대 커밋하지 마세요. `git diff --staged` 점검 후 커밋합니다.

## 워크플로우

```bash
# 1) 최신 master에서 분기
git checkout master
git pull origin master
git checkout -b feat/<짧은-설명>

# 2) 작업 + 자체 검증
poetry run ruff check .          # 백엔드
poetry run mypy app/
poetry run pytest

# 3) 컨벤셔널 커밋 메시지로 커밋
git commit -m "feat(backend): add cycle history pagination"

# 4) 푸시 + PR
git push -u origin feat/<짧은-설명>
gh pr create --base master
```

## 커밋 메시지

[Conventional Commits](https://www.conventionalcommits.org/)을 따릅니다.

```
<type>(<scope>): <imperative summary>

<optional body — explain *why*, not *what*>

<optional footer — refs #123, BREAKING CHANGE: ...>
```

- **type**: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `infra`, `perf`
- **scope**: `ai`, `backend`, `frontend`, `watch`, `infra`, `docs` 등
- 메시지는 명령형 현재시제 (`add`, `fix`, `remove` — `added`/`fixes` 아님)
- 본문은 *왜* 변경했는지에 집중. 무엇을 했는지는 diff가 말해줍니다.

## PR 체크리스트

PR을 열기 전에 본인이 확인:

- [ ] 브랜치 prefix가 규칙에 맞다
- [ ] 커밋 메시지가 Conventional Commits 형식이다
- [ ] 로컬에서 lint / type check / test가 모두 통과한다
- [ ] 시크릿이나 개인 식별 정보가 diff에 들어가지 않았다
- [ ] 사용자에게 영향이 있는 변경(API, UI, 스키마)이면 `backend/docs/` 또는 README에 반영했다
- [ ] DB 스키마 변경은 Alembic 마이그레이션과 다운그레이드 경로를 포함한다

## 리뷰

- 최소 1인 승인 후 머지.
- 리뷰어는 의도(WHY)와 안전성(보안·프라이버시·롤백)을 우선 점검합니다.
- 머지 전략은 **Squash and merge**. 머지 커밋의 제목은 PR 제목을 그대로 사용합니다.
- 머지 후 작업 브랜치는 자동 삭제됩니다.

## 보안 / 프라이버시 변경

다음 영역은 일반 리뷰에 더해 팀 리드 1인의 추가 승인이 필요합니다.

- 인증·세션 코드 (`backend/app/auth/`)
- 옵트인 동의 토글 또는 감사 로그 (`backend/app/consent/`, `backend/app/audit/`)
- 사용자 보유 키 암호화 흐름 (`/api/v1/sync/biosignals`)
- IAM 정책, S3 버킷 정책, 보안 그룹 (`backend/infra/`)

## 이슈

- 버그: 재현 절차, 기대 동작, 실제 동작, 환경(OS/디바이스/앱 버전)을 포함합니다.
- 기능 제안: 해결하고자 하는 사용자 문제를 먼저 적고, 그다음 제안된 해결책을 적습니다.

## 질문

워크플로우/리뷰 정책에 대한 질문은 README §6의 팀 연락처로 보내주세요.
