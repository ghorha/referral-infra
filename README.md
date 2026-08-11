# referral-infra

Composition root for Referral (Vouch) under GitHub org **ghorha**.

- OCI region: **us-phoenix-1** (separate from piraho/Chicago)
- OKE Always-Free Basic + Ampere A1 (arm64)
- Images: `ghcr.io/ghorha/referral-*`
- DB: Neon Postgres
- Frontend: Vercel (`referral-frontend`)
- CI/CD: self-hosted runners `runs-on: [self-hosted, macOS, ARM64]`

See `DEPLOYMENT.md` for bootstrap.
