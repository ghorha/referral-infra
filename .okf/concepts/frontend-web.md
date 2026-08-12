---
okf_version: "0.1"
type: concept
id: frontend-web
title: "Frontend Web App (Next.js 14)"
tags: [nextjs, react, typescript, tailwind, app-router, cookie-auth, axios]
updated: 2026-07-10
related:
  - ../index.md
  - ./design-system.md
  - ./auth-security-architecture.md
  - ./service-api-gateway.md
  - ../playbooks/local-dev-test-build.md
---

# Frontend Web App (Next.js 14)

Location: `frontend/`. Standalone npm project (Next.js `14.0.4`, React 18, TypeScript 5,
Tailwind 3, Axios). Not part of any JS workspace. Product: the Vouch marketplace UI.

## Structure (App Router)

- `app/` — 26 routes, all `page.tsx`; single root `layout.tsx`; no `route.ts` handlers
  (the backend is external).
  - **Public/home:** `/` (listings browse); `/listings` redirects home.
  - **Auth:** `auth/{login,signup,magic-link,callback,forgot-password}`.
  - **Listings:** `listings/create`, `listings/[id]`.
  - **Claims:** `claims/create`, `claims/[id]` (10-step stepper), `claims/[id]/chat`.
  - **User:** `dashboard`, `profile`, `network`, `analytics`, `documents`, `help`.
  - **Admin (role-gated):** `admin/{dashboard,analytics,audit-logs,review,users}`.
  - **Support:** `support/{dashboard,raise-ticket,tickets,tickets/[id],users/[id]}`.
- `components/ui/` — the shared design-system primitives. See [Design System](./design-system.md).
- `components/layout/` — `AppShell`, `SideNav`, `TopAppBar` (desktop bar with notification bell).
- `components/` — `Providers`, `NotificationCenter`, `DisputeModal`, `ErrorBoundary`,
  `auth/ProtectedRoute`, `auth/GoogleSignInButton` (feature-gated off).
- `lib/api/client.ts` — Axios singleton (same-origin baseURL, `withCredentials`, trace-id +
  device-fingerprint headers, idempotent-only 5xx retry, guarded 401→refresh interceptor).
- `lib/auth/context.tsx` — `AuthProvider`/`useAuth`; cookie-based session (no localStorage tokens).
- `lib/device/fingerprint.ts`, `lib/hooks/useApiCache.ts`, `lib/utils/{cn,format}.ts`.

## Backend integration

All calls go to `/api/v1/...` on the **same origin**; `next.config.js` `rewrites()` proxies
`/api/:path*` to the [API Gateway](./service-api-gateway.md) (default `http://localhost:8080`),
making the httpOnly auth cookies first-party. Env: `NEXT_PUBLIC_API_URL`,
`NEXT_PUBLIC_WEBSOCKET_URL`, `NEXT_PUBLIC_GOOGLE_CLIENT_ID`,
`NEXT_PUBLIC_GOOGLE_AUTH_ENABLED`. Auth flow: [Auth & Security](./auth-security-architecture.md).

## Security posture

Cookie auth (no JS-readable tokens); CSP/HSTS/X-Frame-Options/Referrer-Policy/Permissions-Policy
in `next.config.js`; `ProtectedRoute` enforces `requiredRole` client-side (the real gate is the gateway).

## Build, test, run

`npm run dev` (→ :3000), `npm run build` (type-check + ESLint enforced), `npm test` (Jest),
`npm run test:e2e` / `test:smoke` (Playwright). Docker host port `3002→3000`.
See [local dev/test/build](../playbooks/local-dev-test-build.md).

## State (2026-07-10)

Fully migrated to the Vouch 2.0 design system; all pages wired to real endpoints; build green.
Mock-only surfaces (signup real account creation, tickets, some analytics/documents) are shown
as honest "coming soon" rather than faking success.
