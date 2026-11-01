---
name: result-association-and-publication
description: Diagnose or design result association, entity identity, publication queues and visible output acknowledgement in a concurrent pipeline. Use for successful processing followed by missing, duplicated, displaced or stale outputs; not for failures with no valid processing result.
---

# Result Association and Publication

Trace one valid processing result through association, publication decision, queue acceptance, commit, transport and output consumption/acknowledgement where available. Correlate the same run and event before choosing the earliest missing transition.

Read [identity and publication](references/identity-and-publication.md). Keep full content identity, physical entity identity, track/ROI identity, geometry age, source generation and output identity distinct. Prefixes/hashes alone do not prove equality, nor does equal payload prove the same physical pass.

Define association from observed geometry/motion, timing and lifecycle policy. Include cold tracks, ambiguous matches, same-frame duplicates, separate same-content entities and disappearance/re-entry. Preserve ambiguity evidence instead of permanently suppressing content.

Prepare an event before mutating committed state. Commit after required queue acceptance under the actual atomicity contract; preserve uncommitted identity for bounded retry. Queue capacity/backpressure, transport delivery and visible output are separate outcomes. Do not invent an acknowledgement protocol absent from the implementation.

Handle new run, pause/stop, statistics reset, epoch change and restart according to current requirements. Retained identity does not justify retaining stale position. Clear or invalidate old scenes using supported generation/submission behavior.

Verify actual code with event replay, queue shortage, truncation/collision, wrap, restart and stale geometry scenarios. Distinguish function invocation, accepted scene and physical display in results. Return the minimal change, actual retention/capacity assumptions, evidence and remaining target coverage.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
