# Design

## Source of truth

- Status: Active
- Last refreshed: 2026-08-19
- Primary product surfaces: iOS dashboard, daily-task card, sync/account states, widget, diagnostics.
- Evidence reviewed: `FloatingBrain/ContentView.swift`, `FloatingBrainWidget/FloatingBrainWidget.swift`, `project_spec.md`, `README.md`.

## Brand

- Personality: Quietly focused, private, warm, and encouraging.
- Trust signals: Deep indigo surfaces, restrained status colors, clear sync state, and high-contrast task text.
- Avoid: Neon rainbow accents, overly playful gradients, pure black backgrounds, and using red/orange for ordinary emphasis.

## Product goals

- Goals: Make three daily tasks feel calm, legible, and worth acting on; make sync and privacy status immediately understandable.
- Non-goals: Gamification-heavy color, decorative complexity, or color-only status communication.
- Success signals: Users can identify the daily tasks and sync state at a glance in both light and dark appearance.

## Personas and jobs

- Primary personas: One privacy-conscious user resurfacing reminders at home.
- User jobs: Capture reminders quickly, see today’s three tasks, understand whether data is synced, and complete a task without friction.
- Key contexts of use: iPhone in short glances, apartment dashboard, widget, and occasional diagnostics/error recovery.

## Information architecture

- Primary navigation: One dashboard with daily tasks, sync, account, and diagnostics.
- Core routes/screens: Dashboard, all tasks, diagnostics, sign-in.
- Content hierarchy: Today’s three > sync state > account/privacy state > broader task list > diagnostics.

## Design principles

- Calm focus: Reserve the strongest accent for the daily-task action and keep surfaces quiet.
- Honest state: Sync, offline, error, and completion states must be distinguishable without relying on color alone.
- Private by default: Visual language should feel personal and contained, not like a noisy productivity marketplace.
- Tradeoffs: The palette favors indigo and lavender over maximum saturation; status colors are intentionally darker in light mode for contrast.

## Visual language

### Color palette

Use semantic tokens in implementation. Do not reference these raw hex values directly from views.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `canvas` | `#F6F7FB` | `#101426` | App background |
| `surface` | `#FFFFFF` | `#1B2238` | Cards and widget surface |
| `surfaceElevated` | `#FFFFFF` | `#252E49` | Raised controls and modal content |
| `ink` | `#18223F` | `#F7F8FC` | Primary text |
| `inkSecondary` | `#59627A` | `#B7BED3` | Supporting text |
| `border` | `#DDE2EE` | `#39435F` | Dividers and outlines |
| `brandPrimary` | `#51439B` | `#A99CF7` | Primary action, links, active focus |
| `brandDeep` | `#263361` | `#171E38` | Hero gradient start |
| `brandViolet` | `#4D3875` | `#302653` | Hero gradient end |
| `taskAccent` | `#D94F6D` | `#FF8EA5` | Uncompleted task affordance |
| `success` | `#147A67` | `#67D5BA` | Connected, completed, successful sync |
| `warning` | `#8A5A00` | `#F3C56B` | Offline, attention, permission needed |
| `danger` | `#B4232F` | `#FF8B8B` | Errors and destructive actions |
| `info` | `#1769A6` | `#82C7FF` | Informational sync/status detail |

Recommended hero gradient:

```text
brandDeep → brandViolet
```

Recommended task treatment:

```text
taskAccent icon/text → taskAccent at 12% opacity for the task affordance background
```

Accessibility intent:

- Use `ink` for normal text on `canvas`/`surface`.
- Use the dark light-mode status tokens for text or icons on light surfaces.
- Use the lighter dark-mode status tokens for text or icons on dark surfaces.
- Never communicate state by color alone; pair it with an icon, label, or completion mark.
- Validate final rendered combinations against WCAG AA, especially `taskAccent`, `warning`, and `brandPrimary`.

### Typography

- Use the system font with rounded styling for hero headlines and standard system text elsewhere.
- Keep task text at body size or larger; do not trade readability for density.
- Use weight and hierarchy before adding additional color.

### Spacing/layout rhythm

- Base spacing unit: 4 pt.
- Use 16 pt vertical rhythm between dashboard cards and 20 pt horizontal page margins.
- Use 12–16 pt internal card spacing; preserve generous task-row hit areas.

### Shape/radius/elevation

- Cards: 14–16 pt continuous corners.
- Hero: 26 pt continuous corners.
- Primary controls: system bordered/prominent treatments with 12–14 pt rounding.
- Elevation: one restrained shadow level for the hero; rely on tonal surface changes elsewhere.

### Motion

- Prefer native SwiftUI transitions and system interaction feedback.
- Avoid decorative animation on the daily-task surface.
- Respect reduced-motion settings.

### Imagery/iconography

- Use SF Symbols consistently.
- Prefer lock, sparkles, checklist, sync, and status symbols already present in the app.
- Do not introduce illustrations until the core task surface is stable.

## Components

- Existing components to reuse: `MetricTile`, `StatusPill`, `StatusRow`, `MessageBanner`, `DailyTaskRow`, and `cardSurface()`.
- New/changed components: Introduce a central Swift color-token namespace and route existing raw colors through it.
- Variants and states: primary, secondary, task, success, warning, danger, info; each must support light and dark appearance.
- Token/component ownership: Color tokens belong in a shared app-level theme file usable by the widget target where needed.

## Accessibility

- Target standard: WCAG AA-equivalent contrast and native iOS accessibility behavior.
- Keyboard/focus behavior: Preserve system focus indicators and button roles.
- Contrast/readability: Validate text, icons, controls, and status pills in both appearances.
- Screen-reader semantics: Keep labels meaningful without requiring color interpretation.
- Reduced motion and sensory considerations: No required animation; avoid excessive saturation and flashing.

## Responsive behavior

- Supported breakpoints/devices: iPhone layouts and compact widget families; dashboard renderer may use a separate layout.
- Layout adaptations: Preserve task text width and hit targets before adding decorative content.
- Touch/hover differences: Use touch-sized rows and native button states; no hover-only meaning.

## Interaction states

- Loading: Use `info`/neutral styling with progress feedback.
- Empty: Use `inkSecondary` and a concise next action.
- Error: Use `danger` with an explanatory message and recovery action.
- Success: Use `success` with confirmation text or a checkmark.
- Disabled: Reduce contrast through opacity, never by making text unreadably faint.
- Offline/slow network: Use `warning`, explicit “Offline” labeling, and no stale daily-selection resurrection.

## Content voice

- Tone: Short, calm, direct, and encouraging.
- Terminology: Prefer “Today’s three,” “Sync,” “Connected,” and “Offline.”
- Microcopy rules: Explain what happened and the next action; avoid alarmist language.

## Implementation constraints

- Framework/styling system: SwiftUI with system materials and SF Symbols.
- Design-token constraints: Semantic color tokens must be centralized; avoid new raw `Color(red:green:blue:)` values in views.
- Performance constraints: Keep widget rendering lightweight and avoid network work in the widget extension.
- Compatibility constraints: iOS 17+, light/dark appearance, widget extension, and shared app-group presentation data.
- Test/screenshot expectations: Typecheck the app and inspect light/dark dashboard, task, status, and widget states before visual sign-off.

## Open questions

- [ ] Should the Raspberry Pi renderer use the same hex tokens directly, or derive a separate e-paper contrast mapping? / Owner: product / Impact: dashboard consistency.
- [ ] Should the color-token namespace be added in the next UI implementation pass or as a standalone theme refactor? / Owner: engineering / Impact: scope and review size.
