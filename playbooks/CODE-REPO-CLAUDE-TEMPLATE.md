# MediAsk Code Workspace Rules (Template)

> Copy this file to the code repository root as `CLAUDE.md`.
>
> Before use, replace `<DOCS_SUBMODULE_PATH>` with the real path of the MediAsk docs submodule, for example `MediAskDocs`.

## 1. Repository Positioning

- This repository is the implementation workspace for MediAsk code.
- The authoritative documentation baseline lives under `<DOCS_SUBMODULE_PATH>/`.
- Treat `<DOCS_SUBMODULE_PATH>` as `DOCS_ROOT`.
- Do not assume this repository root and `DOCS_ROOT` are the same directory.
- If this repository also has its own `docs/` directory, do not confuse it with `DOCS_ROOT/docs/`.

## 2. Mandatory Reading Order

Before implementation, read these in order:

1. `DOCS_ROOT/CLAUDE.md`
2. Follow the mandatory reading order defined inside `DOCS_ROOT/CLAUDE.md`

If the task is backend, frontend, or full-stack, continue following the task-specific reading set required by `DOCS_ROOT/CLAUDE.md`.

## 3. Core Working Rules

- Prefer changing code to match the documented contract rather than casually changing docs.
- Do not rewrite authoritative docs just because current code differs.
- If you find a real contract bug or outdated statement in docs, call it out clearly before changing the source-of-truth document.
- Keep scope small: one backend task package, one 1~3 page frontend slice, or one full-stack closed loop at a time.
- Do not silently pull `P1` or `P2` content into `P0`.

## 4. Frozen Project Constraints

Unless an authoritative document is intentionally changed, keep these rules fixed:

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

## 5. Docs Submodule Handling

- Files under `DOCS_ROOT/` belong to the docs submodule workspace, not the parent code repository itself.
- If you edit files under `DOCS_ROOT/`, report those changes separately from parent code changes.
- Do not assume a parent repository commit captures uncommitted file changes inside the submodule.
- If the user asks for commits, handle the parent repository and the docs submodule as separate git repositories unless they explicitly say otherwise.

## 6. Progress Writeback Rules

- After implementation and validation, update the required checklists under `DOCS_ROOT/playbooks/` according to `DOCS_ROOT/CLAUDE.md`.
- Only change `[ ]` to `[x]` for items that are both implemented and validated.
- If validation was not run, keep the item unchecked and explain why.

## 7. Completion Standard

A task is not complete until all of the following are true:

- the requested code or page scope is implemented
- the result matches the documented contract
- minimum validation, test, build, or manual verification has been run, or the missing verification is explicitly explained
- the relevant checklist items under `DOCS_ROOT/playbooks/` have been updated honestly
- the work has been checked against `DOCS_ROOT/playbooks/AI-CODE-REVIEW-CHECKLIST.md`

## 8. Final Report Requirements

After finishing a task, report at least:

1. what was implemented in the code repository
2. which files changed in the code repository
3. which files changed under `DOCS_ROOT/`
4. which validation was run
5. which checklist items were updated
6. what the nearest unfinished adjacent item is

## 9. Reporting File References

- Always use concrete paths that include the docs submodule prefix.
- Good: `<DOCS_SUBMODULE_PATH>/docs/00A-P0-BASELINE.md`
- Good: `<DOCS_SUBMODULE_PATH>/playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md`
- Risky: `docs/00A-P0-BASELINE.md`
- If needed, explain the mapping from `DOCS_ROOT/...` to the real mounted submodule path before giving file references.
