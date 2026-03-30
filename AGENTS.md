# DB AGENTS

이 repo 는 schema, migration, rollback, seed, data contract 를 담당한다.

## 시작 전 필수
1. `git checkout main`
2. `git pull --ff-only origin main`
3. `git -C ../docs checkout main`
4. `git -C ../docs pull --ff-only origin main`

## 구현 전 반드시 확인할 문서
- 관련 requirement
- `../docs/04-architecture/data-model-overview.md`
- `../docs/03-conventions/conv-db-naming.md`
- attendance / exam 영향이면 관련 requirement 와 decision
- 서비스 소비자가 누구인지 확인할 수 있는 architecture 문서

## docs gap 규칙
다음이면 구현 중지:
- schema 목표는 있는데 관계/키/제약 설명이 없음
- migration / rollback 기준이 없음
- breaking change 인데 소비 서비스 영향 문서가 없음

이 경우 `$spec-first-dev-guard` 절차를 따른다.

## Git 규칙
- 브랜치: `feat/db/<slug>` 등
- 커밋: `<type>(db): <subject>`
- migration 은 separate commit 권장
- rollback 설명 없는 schema 변경 금지

## 권장 skill
- 개발 전 문서 검증: `$spec-first-dev-guard`
- Git 규약: `$git-governance`
