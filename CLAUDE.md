# MediAsk Docs Workspace Rules

## 1. Repository Positioning

- This repository is the MediAsk documentation baseline and source of truth for architecture, contracts, task breakdown, and execution rules.
- This repository may be used in two ways:
  - standalone, with this repository itself as the workspace root
  - as a Git submodule inside a separate code repository
- Do not assume the current workspace root is this repository root.
- Treat the directory containing this `CLAUDE.md` as `DOCS_ROOT`.
- All document references below are relative to `DOCS_ROOT`.

## 2. Path Resolution Rules

- Before reading any referenced file, first resolve `DOCS_ROOT`.
- If the current workspace already contains both `docs/00A-P0-BASELINE.md` and `playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md`, you are probably already at `DOCS_ROOT`.
- If this repository is mounted as a submodule, prepend the real submodule path to every reference below.
- Never blindly assume bare paths like `docs/...` or `playbooks/...` refer to this repository when working from a parent code repository.
- If the parent repository also has its own `docs/` directory, verify you are using the one that lives under `DOCS_ROOT`.

Examples:

- standalone: `docs/00A-P0-BASELINE.md`
- submodule mounted as `MediAskDocs`: `MediAskDocs/docs/00A-P0-BASELINE.md`

## 3. How To Use This Repository

- Use this repository as the authoritative design baseline when implementing code elsewhere.
- Unless the user explicitly asks to edit documentation, prefer changing code to match the documented contract instead of changing the docs to match current code.
- Do not rewrite authoritative docs casually just because an implementation differs.
- If you discover a real contract bug or outdated statement, call it out clearly before changing the source-of-truth document.

## 4. Mandatory Reading Order

Read these first for any implementation task:

1. `DOCS_ROOT/docs/00A-P0-BASELINE.md`
2. `DOCS_ROOT/playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md`
3. `DOCS_ROOT/playbooks/AI-CODE-REVIEW-CHECKLIST.md`

Then read by task type:

- Backend:
  - `DOCS_ROOT/playbooks/00C-P0-BACKEND-TASKS.md`
  - `DOCS_ROOT/playbooks/00E-P0-BACKEND-ORDER-AND-DTOS.md`
  - `DOCS_ROOT/docs/10A-JAVA_AI_API_CONTRACT.md`
  - `DOCS_ROOT/docs/19-ERROR_EXCEPTION_RESPONSE_DESIGN.md`
- Frontend:
  - `DOCS_ROOT/playbooks/00D-P0-FRONTEND-TASKS.md`
  - `DOCS_ROOT/playbooks/00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md`
  - `DOCS_ROOT/docs/10A-JAVA_AI_API_CONTRACT.md`
  - `DOCS_ROOT/docs/08-FRONTEND.md`
- Full-stack closed loop:
  - read both backend and frontend sets above

## 5. Scope Control

- One task package at a time.
- Backend work: implement one clear task package or one tightly related API/table batch.
- Frontend work: implement only 1 to 3 continuous pages or routes at a time.
- Full-stack work: implement only one continuous closed loop at a time.
- Do not silently expand scope.
- Do not pull `P1` or `P2` content into `P0` unless the user explicitly asks for it.

## 6. Frozen Project Rules

These rules are treated as stable constraints unless an authoritative document is intentionally changed:

- Browser traffic goes to Java only, not directly to Python.
- Java external JSON responses use `Result<T>`.
- `code = 0` means success.
- SSE is forwarded as streaming events and is not wrapped frame-by-frame in `Result<T>`.
- `X-Request-Id` / `request_id` is the single cross-service correlation key.
- Python may write only `knowledge_chunk_index` and `ai_run_citation` as AI-owned persistence.
- AI output scope is limited to symptom organization, risk reminder, care guidance, department recommendation, and citations.
- AI does not output diagnosis conclusions, prescription advice, or dosage guidance.

Frontend-specific rules:

- Page flow is driven by structured fields, especially `nextAction`.
- Do not infer department or risk routing from free-form chat text.
- High-risk pages and normal triage result pages must remain separate.
- Frontend success or failure handling is based on `code`.
- Error states must preserve and expose `requestId`.

## 7. Progress Writeback Rules

- After implementation and validation, update `DOCS_ROOT/playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md`.
- If the task is backend, also update `DOCS_ROOT/playbooks/00C-P0-BACKEND-TASKS.md`.
- If the task is frontend, also update `DOCS_ROOT/playbooks/00D-P0-FRONTEND-TASKS.md`.
- If the task touches ordering, DTOs, or flow confirmation, cross-check `DOCS_ROOT/playbooks/00E-P0-BACKEND-ORDER-AND-DTOS.md` or `DOCS_ROOT/playbooks/00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md`.
- Only change `[ ]` to `[x]` for items that are both implemented and validated.
- If validation was not run, keep the item unchecked and explain why.

## 8. Completion Standard

A task is not considered complete until all of the following are true:

- the requested code or page scope is implemented
- the result matches the documented contract
- minimum validation, test, build, or manual verification has been run, or the missing verification is explicitly explained
- the relevant checklist items have been updated honestly
- the work has been checked against `DOCS_ROOT/playbooks/AI-CODE-REVIEW-CHECKLIST.md`

## 9. Final Report Requirements

After finishing a task, report at least:

1. what was implemented
2. which files were changed
3. which validation was run
4. which checklist items were updated
5. what the nearest unfinished adjacent item is

## 10. Reporting File References

- When speaking to the user from a parent code repository, prefer concrete resolved paths over ambiguous bare references.
- Good: `MediAskDocs/docs/00A-P0-BASELINE.md`
- Good: `MediAskDocs/playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md`
- Risky in a parent repo: `docs/00A-P0-BASELINE.md`
- If needed, first explain the mapping from `DOCS_ROOT/...` to the actual mounted submodule path.
