---
name: systematic-debugging
description: Diagnose a reproducible failure or unexplained regression by validating observations, localizing the first broken boundary and testing competing explanations. Use for software, services, data or hardware faults; avoid imposing a diagnosis workflow on a successful routine edit.
---

# Systematic Debugging

Establish expected versus observed behavior, impact, the current baseline and the change or input that exposes the failure. Inspect relevant source, configuration and raw observations before requesting facts already available. Preserve the user's constraints and scope.

## Make the observation trustworthy

Identify which version, process, package or physical state produced each observation. Source on disk, a built artifact, a selected configuration and an active process/device can differ. Preserve the first useful error and the failing input before a retry changes state.

Check whether the observer is misleading: stale logs, an incorrect parser, wrong environment, retained debugger stops, timing units, partial windows or a failed host tool can imitate a product fault. Treat unavailable access or disconnected equipment as missing evidence, not proof of failure.

## Locate and discriminate

Trace the relevant path into independently observable boundaries. Find the earliest boundary without supporting evidence; a successful downstream counter alone may not prove meaningful data. Read [diagnostic decisions](references/diagnostic-decisions.md) for choosing a bounded experiment.

For the leading plausible explanations record the evidence for/against, the smallest distinguishing action, predicted outcomes and recovery. Choose a change that actually separates explanations. Observe one material factor at a time where practical; when several factors change together, limit causal attribution accordingly.

Use available tools appropriate to the detected environment. Existing authorization applies to scoped actions; this skill does not grant new deployment, destructive cleanup, remote messaging or physical-operation authority. Preserve the known-good state before an experiment that changes it. Bound retries and stop when observations repeat without adding evidence.

## Repair and close

Change the smallest supported fault boundary. Reproduce the original trigger, verify the affected behavior and check the relevant abort/restart/recovery path. Scale regression to the change. A successful build or a matching file hash establishes only that check, not runtime correctness.

Return the observed failure, supported cause or remaining alternatives, executed checks and evidence, changes, results and remaining uncertainty. Distinguish a hypothesis from a confirmed explanation. Keep disproven hypotheses and unsuccessful experiments linked to later corrections.

For specialized work, use [optional capability routing](references/routing.md). The core procedure works without other skills, a particular model, orchestrator, shell or test harness. Specialized checks are additions only when relevant and available.

Read [scope and verification limits](references/provenance.md) when choosing checks or interpreting results.
