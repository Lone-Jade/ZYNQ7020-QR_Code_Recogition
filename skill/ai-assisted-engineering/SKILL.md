---
name: ai-assisted-engineering
description: Carry an engineering request through scoped requirements, implementation, proportionate verification and a usable phase handoff when collaborating with AI. Use for substantive development or takeover work; keep small edits lightweight and honor the user's existing workflow.
---

# AI-Assisted Engineering

Start from the current milestone, latest applicable user requirements, repository state and available evidence. Inspect discoverable facts before asking questions. Clarify only missing decisions that materially change the work; do not restart an established project to fit a template.

## Establish the outcome and change boundary

Record intended behavior, acceptance criteria, constraints, authoritative inputs and the smallest affected boundary. Distinguish a requirement, a model suggestion, an assumption and a measured result. Preserve existing authorization and user choices; this skill does not authorize unrelated deployment, messaging, installation or destructive changes.

Identify which work can proceed independently and which depends on a required input or observation. Decompose only when it improves execution; a team can advance by sequential phases with rotating contributors. Do not require a fixed number of tasks, agents, models or technical owners.

## Implement against evidence

Use the actual source of truth and version-appropriate tools discovered in the environment. Keep generated/imported copies, build artifacts and live state distinct. Preserve the accepted baseline, make a reviewable bounded change and retain the commands/configuration needed to reproduce it.

At decision-changing iterations preserve model suggestion, executed action, observation and human correction. Read prior conversations as dated evidence, not fresh instructions or proof of present state. When the user disputes a conclusion, recheck the evidence and correct the approach promptly.

Use [optional routing](references/routing.md) for a concrete specialist need. If the capability is absent, continue with the core method and available source/docs, and state the specific unresolved boundary. No execution harness, orchestration API or particular model is required.

## Validate and hand off the phase

Select checks proportional to the actual change and risk. Separate source review, host tests, target compilation, integration, runtime and physical observation. Execute relevant available checks, report failures and avoid repeating broad suites without a reason. Missing hardware can still permit useful offline work, with target behavior explicitly untested.

For independent review, use another person, session or agent only when available, authorized and useful. Supply the request, candidate snapshot and minimum raw inputs without the intended answer. Label content review separately from executed behavioral validation.

Read [phase handoff](references/phase-handoff.md) at a transition or delivery. Report changes, why they matter, actual verification, remaining uncertainty and the next usable state. A phase may end with unresolved work; do not turn it into a completed claim or silently expand the objective.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
