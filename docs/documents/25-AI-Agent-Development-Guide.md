# PreviewX — AI Agent Development Guide

## 1. Mission

This document tells AI coding agents how to modify PreviewX safely.

## 2. Before Coding

An agent must:
1. read relevant docs;
2. identify the requirement IDs;
3. inspect existing interfaces;
4. locate tests;
5. state the planned change;
6. avoid unrelated refactors.

## 3. Change Discipline

Every implementation must answer:
- What requirement does this satisfy?
- What API does it touch?
- What tests prove it?
- What security implications exist?
- Does it alter provider routing?

## 4. Never Do

- invent Apple APIs;
- bypass security limits;
- silently add network calls;
- execute previewed files;
- modify source files;
- weaken tests to make a build pass;
- change public interfaces without an ADR.

## 5. Agent Task Template

```text
Task:
Context:
Requirement IDs:
Files likely affected:
Constraints:
Implementation:
Tests:
Acceptance:
Non-goals:
```

## 6. Multi-Agent Parallelism

Safe parallel tracks:
- Provider A
- Provider B
- UI component
- fixture corpus
- documentation

Shared-core changes must be serialized.

## 7. Merge Gate

A change is mergeable only if:
- tests pass;
- formatting passes;
- no public contract changed unexpectedly;
- security checks pass;
- diagnostics are adequate;
- documentation is updated.

## 8. Debugging Protocol

When a test fails:
1. reproduce;
2. minimize fixture;
3. identify layer;
4. fix root cause;
5. add regression test;
6. run focused suite;
7. run full suite.

Do not simply increase timeouts.

## 9. Definition of Done

A task is complete only when implementation, tests, docs, and acceptance criteria all agree.
