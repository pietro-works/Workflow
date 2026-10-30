# Where this fits

A snapshot of what AI-assisted developers are doing on GitHub, taken on 2026-10-27 from public web sources. Almost every number below comes from a blog, a listing site or a vendor guide rather than from GitHub itself, and several sources disagree with each other. Re-check any figure against GitHub before quoting it.

## What's trending

### 1. AGENTS.md is the shared instruction file

OpenAI introduced the format in August 2025, and it was later contributed to the Agentic AI Foundation under the Linux Foundation in December 2025. Adoption counts vary wildly by source, from over 20,000 repositories in an early report, to more than 60,000, to roughly 96,600 root-level files found by GitHub code search in a June 2026 analysis. The direction is clear even if the number isn't. All three counts come from secondary sources in the list below.

The more interesting finding is about quality. A 2026 ETH Zurich study, reported secondhand (I haven't read the study itself), found that README-style instruction files slightly hurt performance and raised token cost, while narrow directives (build commands, gotchas, verification steps) helped. That favors short, non-obvious rules over long project tours.

### 2. Curated lists of skills, hooks and subagents

The community-maintained "awesome" lists have become the discovery layer. `hesreallyhim/awesome-claude-code` was listed at about 47,000 stars in a June 2026 snapshot (SkillRank listing). [`shanraisshan/claude-code-best-practice`](https://github.com/shanraisshan/claude-code-best-practice) sat around 8,000 (Mintlify page). Anthropic's own `anthropics/skills` and `anthropics/claude-code-action` (for CI) show up in nearly every top-ten list. One topic page, GitTrend's AI workflow tag, had [`andrej-karpathy-skills`](https://github.com/multica-ai/andrej-karpathy-skills) at number one in May 2026.

### 3. Skills as files

The pattern that keeps appearing is three layers: `AGENTS.md` for persona and standing rules, `SKILL.md` for a specific procedure, and a separate design or architecture document. Different tools read skills from different folders (`.claude/skills`, `.agents/skills`), so portability is still manual.

### 4. Spec-driven development

GitHub's Spec Kit is the reference implementation, with one learning site (beri.net) putting it near 125,000 stars. The workflow runs constitution, specify, plan, tasks, implement, and it advertises support for 35 or more coding agents. The idea is that specs are executable artifacts, not scaffolding that gets thrown away.

### 5. Compaction plus memory files

The standard answer to long sessions is to compact the conversation and keep anything important in durable files. The reported failure modes are consistent: compacted agents re-read files they had already processed and retry operations that had already failed. One April 2026 post scored compacted agents at about 4.0 out of 10 against 6.0 for agents with intact context, which is a single benchmark and not a law. Research is moving toward letting the agent decide when to compress (CliffCompaction, a September 2026 arXiv paper, reports cutting cost by up to 50% under a bounded context on Terminal-Bench and KernelBench, per its abstract).

### 6. Share of agent-written commits

A vendor guide from Fast.io claims Claude Code wrote roughly 12% of public GitHub commits by mid-2026. I couldn't confirm the figure, so treat it as unverified.

## How this setup compares

| Ecosystem direction | This setup |
| --- | --- |
| One shared instruction file across tools | `CLAUDE.md` is the source of truth and `AGENTS.md` points to it, so tools that look for either land in the same place |
| Skills, hooks and subagents from curated lists | Hooks gate edits on the PACS registry. Subagents run the three-agent sweep. Skills are used for recurring work but aren't published here |
| Spec-first workflows | Not used. The adversarial pre-change pass fills a similar planning role without a written spec |
| Compaction plus memory files | Same direction. headroom compresses tool output before the model sees it, and the PACS hook clears its marker on every session start, compaction included |
| Logging what an agent changed | A per-change trace with an invariant, proof and rollback on each line |
| Silent-coupling markers | PACS, with a public linter and spec |

## Gaps worth closing

- **The instruction file is long.** At 298 lines it is mostly rules an agent can't infer from code, which the reported research favors, but the Humanization section alone runs about a hundred lines.
- **No CI check.** `pacs check` could run on every push in projects that carry a registry.
- **Skills aren't published.** The recurring procedures exist, but not as portable `SKILL.md` folders.
- **No spec step.** For larger features, a short written spec before the adversarial pass might catch design errors earlier.

## Sources

- [GitTrend, AI workflow topic](https://gittrend.io/trending/ai-workflow)
- [Analytics Insight, best GitHub repos to learn Claude Code](https://www.analyticsinsight.net/artificial-intelligence/best-github-repos-to-learn-claude-code-in-2026-top-10-picks)
- [KDnuggets, 10 GitHub repositories to master Claude Code](https://www.kdnuggets.com/10-github-repositories-to-master-claude-code)
- [hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code)
- [Harness, the agent-native repo and AGENTS.md](https://www.harness.io/blog/the-agent-native-repo-why-agents-md-is-the-new-standard)
- [AGENTS.md as an open standard under Linux Foundation governance](https://codex.danielvaughan.com/2026/04/07/agents-md-open-standard-cross-tool-portability/)
- [Ry Walker, AGENTS.md standard research](https://rywalker.com/research/agents-md-standard)
- [GitHub Spec Kit overview](https://www.beri.net/learning/github-spec-kit)
- [Context compaction deep dive across Codex CLI, Claude Code and OpenCode](https://codex.danielvaughan.com/2026/04/14/context-compaction-deep-dive-codex-cli-claude-code-opencode/)
- [Compaction traps in long-running agents](https://tianpan.co/blog/2026/04/19/compaction-traps-long-running-agents)
- [SentinelOne Labs, context engineering and compaction](https://www.sentinelone.com/labs/context-engineering-compaction-agent-memory-for-automated-malware-analysis/)
- [CliffCompaction (arXiv)](https://arxiv.org/pdf/2609.26779)
- [Fast.io, Claude Code guide](https://fast.io/resources/everything-claude-code-guide/)
