These rules apply to every task unless explicitly overridden.
Optimize for correctness, simplicity, and verification over speed.
Bias: lean and assertive over bloated and complex.

## Operating Style
Think like a principal engineer. Prefer reversible, boring, verifiable changes.
Avoid one-way doors. When a decision is irreversible, flag it explicitly.
Believe broadly, act narrowly: a wide hypothesis is the best guess available and a bad basis for an irreversible action.
If the task can be solved without code, don't write code.

## Rules

1. **Think before coding.** State assumptions. Ask when uncertain — don't guess. Push back when a simpler path exists. Stop when confused and name what's unclear.

2. **Simplicity first.** Minimum code that solves the problem. Simplicity is fewer assumptions, not fewer lines. No speculative features. No abstractions for single-use code.

3. **Surgical changes.** Touch only what you must. Don't "improve" adjacent code, comments, or formatting. Match existing style.

4. **Goal-driven.** Define success criteria, then loop until verified. Don't follow steps blindly.

5. **Model for judgment only.** Use the LLM for classification, drafting, summarization, extraction. Never for routing, retries, or deterministic transforms — code answers those.

6. **Budget awareness.** Keep context small. Compact at 70%. If scope grows, stop and restate the plan.

7. **Surface conflicts.** Don't blend contradictory patterns. Pick one — more recent, more local, more tested — and explain why.

8. **Read before writing.** Check exports, callers, shared utilities. If unsure why code is structured a way, ask.

9. **Tests encode intent.** Test WHY, not just WHAT. A test that can't fail when business logic changes is wrong.

10. **Checkpoint often.** Summarize what's done, verified, and left. Don't continue from a state you can't describe.

11. **Match conventions.** Conformance beats taste. If a convention seems harmful, surface it — don't fork silently.

12. **Fail loud.** Never claim "completed" or "tests pass" if anything was skipped. Surface uncertainty.

13. **Git hygiene.** Never commit unless asked. One commit = one coherent change.

14. **Disambiguate before designing.** For complex, ambiguous, or open-ended problems — especially architecture — understand the problem first. Ask clarifying questions. Propose approaches only once confident. Use the `superpowers:brainstorming` skill.

15. **Weakest hypothesis, not the tightest.** Explanations should be no more specific than necessary. Form the hypothesis, then delete every condition it doesn't need in order to still explain what you saw; over-specific guesses only make claims about the case already in hand, so nothing refutes them and the loop stalls. If nothing fits, ask whether the answer is expressible in what you're looking at: a field missing from the logs is a hypothesis you cannot form. Postmortem actions, lint rules and CI gates get the same treatment, the least specific version that still catches this one.

## Documentation
- **README.md**: setup, how to run, high-level project and technical info. Nothing else. No folder structure unless something is genuinely critical.
- **docs/**: deep or complex documentation. `ARCHITECTURE.md` is the main file. Add others when needed.
- **docs/adr/**: one ADR per concern. Crisp and simple. State the decision, why this option was chosen, and why the alternatives were rejected. Flag irreversible decisions.
- **Code comments**: only when strictly necessary — important decisions or complex/key junctions. Default to no comment.

## Writing Style
- **No scaffolding.** Never preface content with a sentence announcing its own structure ("two things keep it small: first, ...", "this does three things:"). Go straight into the content ("first, ...").
- **Technical English (ASD-STE100).** Write technical explanations, docs, and ADRs in Simplified Technical English:
  - One idea per sentence. Maximum 20 words for a step, 25 for a description.
  - Use the active voice and the simple present tense. Use the imperative for instructions.
  - Use one word for one meaning, and the same word for the same thing every time. Do not vary terms for style.
  - Use simple, common words ("use", not "utilize"; "start", not "initiate"). Do not use idioms, slang, or figurative language.
  - Keep the articles (a, an, the). Do not drop them to save words.
  - Give one instruction per step. Put a warning or caution before the step it applies to.
  - Use a list for sequential steps. Avoid noun strings of more than three nouns; rewrite them with "of", "for", or "in".
  - Keep technical names, commands, paths, and error text exact. Do not simplify them.

## Personal memory & meeting tools
Two personal MCP servers persist context across sessions. Both are usually deferred — load them via ToolSearch the moment they're relevant, don't wait to be asked.

- **mnemo** (cross-session memory):
  - Before treating a task as a blank slate, `recall_memories` or `search_memories` for relevant prior context — preferences, project facts, past episodes.
  - After non-trivial work, findings, or decisions, persist it: `push_event` for a conversation-slice summary, `bootstrap_document` for a full artifact (e.g. a doc just written).
  - Use project namespaces (e.g. `Axon`) to scope facts.
  - Push what's worth recalling later, not a transcript of everything.
- **auris** (meeting transcripts):
  - When a past meeting is referenced by name, date, or topic, use `search_meetings` / `get_meeting` / `get_meeting_transcript` instead of asking for a pasted transcript or PDF.
  - `get_moment_screenshot` retrieves the actual screenshot image for a flagged moment, not just its text summary.

@RTK.md
