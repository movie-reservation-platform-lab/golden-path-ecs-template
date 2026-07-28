# Implementation Plan: Hybrid Teaching Mode Skill

> **Delivered:** 2026-07-28. The canonical skill, metadata, generated
> tool-specific copies, and guidance indexes were created and validated.

## 1. Summary

Add a portable repository skill that turns AI-assisted implementation into a
guided practice loop. The AI may inspect, explain, research, plan, scaffold
mechanical code, and review work, while the engineer owns at least one
meaningful implementation slice.

Keep the existing always-on teaching rule unchanged. Make the stricter workflow
a separate skill so it activates for learning-first work, coding-fatigue
recovery, or explicit requests to avoid black-box implementation.

## 2. Goals

- Require an explicit AI-owned and engineer-owned work split.
- Make the engineer predict, choose, implement, debug, or explain a meaningful
  part of the change.
- Provide graduated help without withholding useful research or feedback.
- Support TypeScript, NestJS, frontend, tests, and AWS CDK work in this
  repository.
- Remain portable across the repository's Cursor, Codex, Claude, Roo, and Gemini
  generated skill directories.

## 3. Non-goals

- Ban AI assistance or shame the engineer for requesting more help.
- Turn every repository task into a tutorial.
- Add time tracking, a learning journal, hooks, dependencies, or runtime code.
- Prevent the user from explicitly opting out for a task.

## 4. Current State

- `.ai/rules/teaching-mode.md` requires explanations and codebase-specific
  teaching, but it does not reserve implementation work for the engineer.
- `.ai/skills/` is the canonical skill source.
- `.ai/sync.sh` copies canonical skills into tool-specific directories and
  rebuilds the generated guidance indexes.
- `.ai/meta/` supplies descriptions for generated indexes.

## 5. Requirements and Assumptions

### Confirmed Requirements

- Create the skill under `.ai/skills/`.
- Allow AI-created boilerplate while preventing a complete black-box solution.
- Let the engineer continue to ask for guidance, research, articles, debugging
  help, and implementation assistance.
- Use relevant ideas from current Cursor, Codex, and Claude-compatible skill
  banks.

### Assumptions

- The skill is strict once active, but it is not an always-on repository rule.
- A meaningful engineer contribution can be a test, domain decision,
  implementation branch, debugging hypothesis, CDK resource choice, or
  teach-back.
- An explicit full-solution override is allowed; the AI must make the mode
  change visible and preserve a small verification or teach-back step.

### Open Questions

- None block implementation. Strictness can be tuned after using the skill on a
  real feature.

## 6. Proposed Design

Create `hybrid-teaching-mode` with four parts:

1. Establish one learning target and a small implementation contract.
2. Split work into AI-owned mechanical work and engineer-owned reasoning or
   implementation.
3. Use a help ladder: question, conceptual hint, code pointer, pseudocode or
   signature, partial code, then an explicit full-solution override.
4. Finish with verification plus a short engineer explanation of what changed
   and why.

Adapt these patterns:

- OpenAI and Anthropic skill creators: precise trigger metadata, concise core
  workflow, progressive disclosure.
- Cursor Agent Skills: portable `SKILL.md` packaging for procedural guidance.
- `learn-codebase`: ask before telling, predict before revealing, active recall,
  and graduated hints.
- Superpowers: small checkpoints, test-first behavior, and evidence before
  completion claims.

## 7. Alternatives Considered

### Alternative A: Strengthen the Always-on Teaching Rule

- Pros: Applies automatically to every task.
- Cons: Makes urgent, mechanical, and non-learning work unnecessarily
  interactive.
- Decision: Reject. Keep explanation and implementation ownership as separate
  levels of assistance.

### Alternative B: Add a Separate Hybrid Skill

- Pros: Strong behavior when relevant, explicit invocation, portable, and easy
  to iterate.
- Cons: Relies on correct triggering or manual invocation.
- Decision: Use this approach.

### Alternative C: Make the AI Read-only

- Pros: Maximizes manual practice.
- Cons: Discards useful scaffolding, repository exploration, command execution,
  and review help; likely increases fatigue.
- Decision: Reject. The goal is deliberate practice, not artificial friction.

## 8. API / Interface Changes

Add the `$hybrid-teaching-mode` skill invocation and matching discovery
metadata. No application API changes.

## 9. Data Model / Persistence Changes

None.

## 10. Security, Privacy, and Abuse Considerations

- Do not weaken normal secret-handling, validation, IAM, or destructive-action
  safeguards during teaching.
- Do not use fatigue as a reason to conceal safety-critical implementation
  details.
- Allow the AI to take over mechanical or safety-critical corrections when
  delay would create risk, while explaining the change.

## 11. Performance, Scalability, and Reliability Considerations

The skill has no runtime cost. Keep exchanges and engineer-owned slices small
enough that the workflow reduces fatigue rather than adding ceremony.

## 12. Implementation Steps

1. Create the canonical skill
   - Change: Initialize and write the guided implementation workflow.
   - Files/modules likely affected:
     `.ai/skills/hybrid-teaching-mode/SKILL.md` and
     `.ai/skills/hybrid-teaching-mode/agents/openai.yaml`.
   - Verification: Run the skill validator.

2. Register the skill
   - Change: Add canonical metadata for generated indexes.
   - Files/modules likely affected: `.ai/meta/hybrid-teaching-mode.yaml`.
   - Verification: Inspect the generated index entry.

3. Publish generated copies
   - Change: Run `.ai/sync.sh`.
   - Files/modules likely affected: tool-specific skill directories and
     generated guidance indexes.
   - Verification: Confirm each generated skill matches the canonical source.

4. Review realistic pressure cases
   - Change: Check feature, debugging, repeated-help, fatigue, and opt-out
     scenarios against the written rules.
   - Files/modules likely affected: canonical `SKILL.md` if loopholes appear.
   - Verification: Document the scenario outcomes in the handoff summary.

## 13. Testing Strategy

- Run the skill-creator `quick_validate.py` against the canonical skill.
- Run `bash -n .ai/sync.sh`.
- Run `.ai/sync.sh`.
- Compare generated copies with the canonical files.
- Inspect only the documentation/configuration diff; do not run application
  tests for this documentation-only change.

## 14. Rollout / Migration Plan

No migration is required. Invoke the skill on a small upcoming feature first.
If the pacing is too strict or too loose, adjust the canonical skill and rerun
the sync script. Removing the skill and its metadata fully rolls back the
change.

## 15. Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
| --- | ---: | ---: | --- |
| The AI still completes the meaningful code | High | Medium | Define learner-owned files or symbols before editing and prohibit silent takeover. |
| The workflow adds more fatigue | Medium | Medium | Limit practice to one small slice and offer a low-energy mode. |
| The AI withholds help when the engineer is stuck | Medium | Medium | Use a graduated help ladder and explicit override. |
| The skill triggers for routine work | Low | Medium | Use a narrow description tied to learning intent and fatigue signals. |
| Tool copies drift | Medium | Low | Keep `.ai/` canonical and publish through `.ai/sync.sh`. |

## 16. Done Criteria

- The canonical skill and metadata exist.
- The skill defines ownership, help escalation, completion, and opt-out rules.
- Generated Cursor, Codex, Claude, Roo, and Gemini copies exist.
- Validation and sync checks pass.
- The final diff contains no unrelated edits.

## 17. Review Checklist

- [x] Requirements are explicit
- [x] Non-goals are explicit
- [x] Existing code conventions were checked
- [x] Alternatives were considered
- [x] Security implications were reviewed
- [x] Scalability and reliability implications were reviewed
- [x] Testing strategy is complete
- [x] Rollout and rollback are defined
- [x] Implementation steps are ordered and concrete

## 18. Handoff Prompt for Implementation Agent

```text
Implement docs/plans/hybrid-teaching-mode-skill.md.

Create the canonical skill under .ai/skills/hybrid-teaching-mode, add its
.ai/meta entry, validate it with the skill-creator tools, and run .ai/sync.sh.
Preserve unrelated worktree changes. This is documentation/configuration work;
do not run application tests.
```
