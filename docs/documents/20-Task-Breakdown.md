# PreviewX — Task Breakdown

## 1. Phase 0 — Repository Bootstrap

- [ ] Create Xcode workspace.
- [ ] Create PreviewX app target.
- [ ] Create Quick Look Preview Extension target.
- [ ] Create Swift Package modules.
- [ ] Configure CI.
- [ ] Add linting/formatting.
- [ ] Add test fixture repository.

## 2. Phase 1 — Core Runtime

- [ ] Implement `PreviewRequest`.
- [ ] Implement `PreviewDocument`.
- [ ] Implement provider protocol.
- [ ] Implement provider registry.
- [ ] Implement deterministic router.
- [ ] Implement resource budgets.
- [ ] Implement cancellation.
- [ ] Implement diagnostics.

## 3. Phase 2 — Quick Look

- [ ] Register initial UTTypes.
- [ ] Implement preview extension.
- [ ] Route Finder requests into PreviewRuntime.
- [ ] Render basic text.
- [ ] Validate Spacebar workflow.

## 4. Phase 3 — Providers

- [ ] Text.
- [ ] Code.
- [ ] JSON.
- [ ] YAML.
- [ ] TOML.
- [ ] XML.
- [ ] CSV.
- [ ] Markdown.
- [ ] Logs.
- [ ] Archive.

## 5. Phase 4 — Security

- [ ] Resource budgets.
- [ ] archive traversal protection.
- [ ] symlink policy.
- [ ] parser fuzzing.
- [ ] secret detection.
- [ ] remote AI policy.

## 6. Phase 5 — UX

- [ ] Search.
- [ ] line navigation.
- [ ] tree view.
- [ ] metadata footer.
- [ ] error states.
- [ ] accessibility.

## 7. Phase 6 — AI

- [ ] AI provider abstraction.
- [ ] local provider.
- [ ] remote provider.
- [ ] consent UI.
- [ ] redaction.
- [ ] selected-content analysis.

## 8. Phase 7 — SDK

- [ ] Public provider API.
- [ ] Manifest schema.
- [ ] SDK test harness.
- [ ] example plugin.
- [ ] compatibility checker.

## 9. Phase 8 — Release

- [ ] signing.
- [ ] notarization.
- [ ] update mechanism.
- [ ] crash diagnostics.
- [ ] documentation.
- [ ] release automation.

## 10. Agent Work Rules

Each agent task must include:
- objective
- inputs
- expected files
- tests
- acceptance criteria
- non-goals
- dependencies

Agents must not silently change public contracts.
