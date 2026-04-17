# TODO #001 — SDF-Sage Dynamic Model Discovery

> **Priority:** 🟡 P2 — Medium
> **Status:** 📋 Preparing
> **Branch:** —
> **PR:** —
> **Created:** 2026-04-17
> **Shipped:** —

---

## Problem Statement

The current `before.sh.erb` hard-codes a fixed model list in `opencode.json` for SDF-Sage
users. This means:

- Only models we know about at development time are listed
- Users with access to a different or larger set of models cannot use them
- When new models are added to the SDF-Sage platform, the OOD app must be manually updated

The SDF-Sage platform routes models per `facility:repo` allocation — different users
(and different repos within the same facility) may have access to a different set of models.
We cannot know at form-submission time which models a given user can actually use.

### What fails today

| Scenario | Current behaviour | Desired behaviour |
|----------|-------------------|-------------------|
| User has access to a model not in our hard-coded list | Model is not available in opencode | All accessible models appear in opencode |
| New model added to SDF-Sage | OOD app shows nothing until manually updated | New model appears automatically |
| User's allocation only covers a subset of models | Opencode shows models they can't use | Only usable models are shown |

---

## Goals

1. `opencode.json` is populated with the full set of models available to the user's `facility:repo` at session start
2. No manual update to the OOD app is required when the SDF-Sage platform adds new models
3. Model discovery happens during `before.sh.erb` execution (before opencode launches)
4. Failure to discover models degrades gracefully — falls back to a known-good default list rather than crashing

## Non-Goals

- Real-time model availability updates during a running session
- Caching model lists across sessions (discovery runs fresh each time)
- Support for non-SDF-Sage providers (Bedrock model list is static and known)

---

## Design

### Open Questions (must resolve before design)

1. **Does the SDF-Sage LiteLLM proxy expose a `/v1/models` endpoint?**
   Most OpenAI-compatible proxies do. If so, we can `curl` it with the user's token
   after `s3df login` to get the live model list.
   — Recommendation: test `curl https://llm.sdf.slac.stanford.edu/v1/models` with a
   valid S3DF token and inspect the response.

2. **What authentication does `/v1/models` require?**
   Likely the same Bearer token from `~/.s3df-access-token`. Needs verification.

3. **What is the model ID format returned by the endpoint?**
   e.g. `facility:repo/provider/claude-sonnet-4.6` or just `claude-sonnet-4.6`?
   The format needs to match what we put in the `models` block of `opencode.json`.

4. **Should s3df login happen in `before.sh.erb` or `script.sh.erb`?**
   Currently in `script.sh.erb` so the user sees the auth URL in the terminal.
   But model discovery in `before.sh.erb` needs the token — this ordering must be resolved.
   — Recommendation: move s3df login to `before.sh.erb`, or do a token-presence check
   first and only re-auth if needed.

---

## Implementation Plan

*To be filled in once Open Questions above are resolved.*

---

## Implementation Checklist

- [ ] Verify `/v1/models` endpoint exists and returns model list
- [ ] Determine auth mechanism for model list endpoint
- [ ] Determine model ID format and map to opencode.json structure
- [ ] Resolve s3df login ordering (before.sh.erb vs script.sh.erb)
- [ ] Write model discovery script in `before.sh.erb`
- [ ] Implement graceful fallback if discovery fails
- [ ] Test with a real SDF-Sage allocation
- [ ] Update `k8s-access` skill with any new operational notes

---

## Problems & Solutions

<!-- Add entries as encountered -->

---

## Open Questions

1. **Does `https://llm.sdf.slac.stanford.edu/v1/models` return a per-allocation model list?**
   — Recommendation: test with `curl -H "Authorization: Bearer $(cat ~/.s3df-access-token)" https://llm.sdf.slac.stanford.edu/v1/models`

2. **Where should s3df login happen?** Currently `script.sh.erb` (terminal-visible auth URL),
   but `before.sh.erb` needs the token for model discovery.
   — Recommendation: move login to `before.sh.erb` and export the terminal output path so
   the user still sees the auth prompt.

3. **Fallback model list** — if discovery fails, what should we fall back to?
   — Recommendation: use the current hard-coded list (`claude-sonnet-4.6`, `claude-haiku-4.5`)
   as the fallback, with a warning printed to the session log.
