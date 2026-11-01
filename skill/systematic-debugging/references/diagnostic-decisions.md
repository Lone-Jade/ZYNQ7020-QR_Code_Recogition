# Choosing useful evidence

Match the evidence to the assertion. A listening service does not prove an authenticated request succeeded; accepted work does not prove completion; successful transport does not prove current input or correct output. Inspect the operation behind a counter and correlate source/run/request identities.

Separate observer failures from system failures. Verify an interpreter/import error, capture timeout or missing trace before interpreting an empty result. Preserve event ordering and clock domains; timestamps from different hosts need an established relationship. Use complete relevant logs rather than a single final summary.

An experiment should distinguish at least two plausible explanations. State what each outcome would mean and how to restore the baseline. Prefer a harmless observation or isolated replay when it can answer the question. Readiness checks should support the next action, not become an unrelated full audit.

When an intermittent failure disappears, record the conditions and coverage; absence in a short run does not prove elimination. Preserve the failing input and instrumentation where possible. After a user correction, recheck the disputed inference against raw evidence before defending it.

For concurrent pipelines, trace ownership and generation across the whole consumer lifetime. A slot valid at acquisition may be reused before the consumer finishes. Completion, visibility, publication and physical output can be separate transitions. Use the appropriate specialist only when this boundary matters.

For logs alone, return supported hypotheses and a discriminating next check. If the user ends testing or changes the requirement, report what remains untested without automatically starting another experiment.

Historical roots: layered camera/stream, standalone startup and Linux runtime failures across four team source cohorts. The procedure deliberately omits their board addresses, tool releases, fixed experiment budgets and model-specific interfaces.
