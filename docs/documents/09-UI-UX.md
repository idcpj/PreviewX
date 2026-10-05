# PreviewX — UI/UX Specification

## 1. Design Goal

The Quick Look preview should feel native to macOS while adding developer-specific information without becoming an IDE.

## 2. Layout

```text
┌─────────────────────────────────────────────┐
│ filename.ext                       ● status │
├─────────────────────────────────────────────┤
│ toolbar: search | line | raw | tree | AI   │
├─────────────────────────────────────────────┤
│                                             │
│              preview content                │
│                                             │
├─────────────────────────────────────────────┤
│ type · size · encoding · provider · timing │
└─────────────────────────────────────────────┘
```

## 3. Interaction

Primary:
- Spacebar opens preview
- Esc closes
- Cmd+F searches where supported
- Cmd+L jumps to line where supported

Do not add modal dialogs for ordinary parse errors.

## 4. Themes

Use system appearance by default:
- light
- dark
- high contrast

Syntax colors must remain accessible and should not be the only carrier of meaning.

## 5. Accessibility

- VoiceOver labels
- keyboard navigation
- reduced motion
- scalable text
- sufficient contrast
- semantic tree/table structures

## 6. Empty/Error States

Every state answers:
1. What happened?
2. Why?
3. What can the user do next?

## 7. AI UI

AI actions are explicit:
- Explain this file
- Summarize log
- Find suspicious entries
- Explain selected block

Never place "Analyze with AI" as an automatic network-triggering action.

## 8. Acceptance

- All primary actions keyboard accessible.
- Preview remains readable at large font sizes.
- Error state is understandable without developer terminology.
