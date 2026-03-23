---
name: sub-agent-dispatch
description: "Patterns for dispatching sub-agents with structured instructions. Covers parallel dispatch, gating, and result collection. Used by AnalystAgent."
---

# Sub-Agent Dispatch Patterns

> **Related skills:** `orchestration/pipeline-flow`, `orchestration/reporting`

## Dispatch Format

When invoking a sub-agent, always provide:

1. **Clear task description** — what to do
2. **Input artifacts** — what to read
3. **Output expectations** — what to produce
4. **Skills to load** — which skills the agent should use
5. **Completion criteria** — how to know it's done

## Template: Single Agent Dispatch

```
Invoke [AgentName]:
- Task: <one-line description>
- Read: <input files/folders>
- Produce: <expected output files>
- Skills: <relevant skill paths>
- Done when: <completion gate>
```

## Template: Parallel Agent Dispatch

When dispatching agents in parallel, ensure:
- **No write conflicts** — agents write to separate paths
- **Shared reads are immutable** — input docs don't change during execution
- **Independent completion** — each agent's success is independent

```
Dispatch in parallel:
  Agent A: [task] → writes to [path A]
  Agent B: [task] → writes to [path B]
Gate: Both A and B must complete before next phase.
```

## Result Collection

After each sub-agent completes, collect:

| Field | Description |
|-------|-------------|
| Agent | Which agent ran |
| Status | Success / Failed / Partial |
| Files Created | List of new files |
| Files Modified | List of changed files |
| Issues Found | Bugs, ambiguities, blockers |
| Duration | Rough time estimate |

Store results for the Phase 6 report (see skill: `orchestration/reporting`).

## Phase-Specific Dispatch Instructions

### Phase 2: DeveloperAgent

```
Task: Implement Java 21 code from translation specs
Read: translation/INDEX.md, translation/*.md
Produce: java-implementation/src/main/java/**/*.java, pom.xml
Skills: development/frontmatter-navigation, development/implementation-workflow,
        development/type-mapping, development/record-parsing,
        development/data-generation, development/java-patterns,
        development/code-checklist, build/build-validation
Done when: mvn clean compile succeeds, all classes implemented
```

### Phase 2: TesterAgent (parallel with Developer)

```
Task: Write comprehensive tests from translation specs
Read: translation/INDEX.md, translation/*.md
Produce: java-implementation/src/test/java/**/*Test.java
Skills: testing/test-planning, testing/unit-testing,
        testing/integration-testing, testing/mocking,
        testing/test-data, testing/test-execution
Done when: Test files created, test plan documented
```

### Phase 3: SecurityAgent

```
Task: Scan Java code for vulnerabilities
Read: java-implementation/ (*.java, *.xml)
Produce: security-reports/security-report.md
Skills: security/code-scanning
Done when: Security report exists with findings and recommendations
```

### Phase 4: DeveloperAgent (security fixes)

```
Task: Fix CRITICAL and HIGH vulnerabilities from security report
Read: security-reports/security-report.md
Produce: Fixed files in java-implementation/
Skills: development/code-checklist, build/build-validation
Done when: All CRITICAL/HIGH fixed, mvn clean compile passes
```

### Phase 5: DiagramAgent

```
Task: Generate C4 PlantUML diagrams
Read: java-implementation/, translation/
Produce: docs/diagrams/c4/level*/*.puml, docs/diagrams/README.md
Skills: diagrams/plantuml-links
Done when: All 4 C4 levels generated, URLs created
```

## Error Handling

| Scenario | Action |
|----------|--------|
| Sub-agent fails | Log error, retry once, then flag in report |
| Sub-agent produces incomplete output | Note in report, proceed if non-blocking |
| Gate not met | Do NOT proceed — debug and retry |
