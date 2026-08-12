---
okf_version: "0.1"
type: concept
id: design-system
title: "Design System (Vouch 2.0)"
tags: [design-system, material-3, tailwind, components, next-font, accessibility]
updated: 2026-07-10
related:
  - ../index.md
  - ./frontend-web.md
---

# Design System — "Vouch 2.0 · Confident Trust"

A bold editorial-fintech Material‑3 system layered on the Vouch brand (Sapphire
`#003c90` + Emerald `#006c49`). Source spec: root `DESIGN.md`. Implemented in
`frontend/` and consumed by all [frontend](./frontend-web.md) pages.

## Tokens — `frontend/tailwind.config.js`

- **Color:** full tonal scales `primary-50..950`, `secondary-*`, `tertiary-*`, `error-*`,
  a new `warning-*` (amber) scale, plus the Material‑3 role tokens (`surface`,
  `surface-container-*`, `on-surface`, `outline-variant`, …). Adding the tonal scales
  fixed the critical defect where `bg-primary-700`‑style utilities emitted **no CSS**
  (invisible CTAs across the back-office).
- **Type:** `Bricolage Grotesque` (display), `Hanken Grotesk` (UI/body), `JetBrains Mono`
  (money/stats/ids) — loaded via `next/font` in `app/layout.tsx` (self-hosted, no remote
  double-load). Tokens: `text-display-*`, `text-h1/2/3`, `text-body-*`, `text-label-*`, `text-eyebrow`.
- **Motion/depth:** keyframes (`fade-up`, `scale-in`, `shimmer`, `pulse-ring`, …), a
  `stagger` helper, brand-tinted shadows (`card`, `card-hover`, `elevated`), gradient-mesh
  backgrounds. `prefers-reduced-motion` respected globally (`app/globals.css`).

## Shared primitives — `frontend/components/ui/`

Single source of truth (replaced ~5 input recipes / 13 badge variants / 3 button recipes):
`Button`, `Card`, `Input`, `Select`, `Textarea`, `StatusBadge` (one status→tone map),
`Chip`, `Spinner`/`PageSpinner`, `Skeleton`/`SkeletonCard`, `EmptyState`, `ErrorState`
(with retry), `Avatar`, `PageHeader`, `Stat`, `Modal` (accessible: focus-trap + Escape),
`Stepper` (the signature 10-step transaction flow), `Icon` (Material Symbols wrapper).
Barrel export at `components/ui/index.ts`. Helpers: `lib/utils/format.ts`
(`formatAmount` cents→USD, `formatDollars`, `formatDate`, `formatRelative`, `humanize`,
`initials`) and `lib/utils/cn.ts`.

## Conventions

- **Never** use raw palette colors (`gray-*`, `slate-*`, `purple-*`, …) or raw hex — only
  design tokens.
- Money via `formatAmount`/`formatDollars` in `font-mono tabular-nums`.
- Every data fetch renders **loading / error(+retry) / empty** states.
- Interactive cards/rows are real `button`/`a` or have `role`+`tabIndex`+key handlers;
  dialogs use the accessible `Modal`.
- App chrome via `AppShell` (+ `SideNav`, desktop `TopAppBar`) — see [Frontend](./frontend-web.md).
