---
okf_version: "0.1"
type: concept
id: service-notification
title: "Notification Service"
tags: [notifications, websocket, stomp, email, push, spring-boot, postgres, realtime]
port: 8087
updated: 2026-07-10
related:
  - ../index.md
  - ./data-model.md
  - ./service-claim.md
  - ./frontend-web.md
---

# Notification Service

## Purpose
The Notification Service is the platform's central fan-out point for user-facing alerts. It persists in-app notifications (claim status changes, new messages, listing expiry, payout received, system announcements), exposes a REST API the web frontend uses to render the notification bell and mark items read, and pushes real-time updates over a STOMP WebSocket. It also contains the internal delivery pipeline that respects each user's per-post/global subscription settings and frequency preference (instant / digest / none), dispatching to email, push, and SMS channels — all of which are stubbed/disabled in local dev.

## Runtime
- **Port**: 8087
- **Base package**: `com.referralmarketplace.notification`
- **Stack**: Spring Boot 3.2.0 / Java 17
- **Dir**: `services/notification-service`

## API
All routes are under `/api/v1/notifications` (`NotificationController`).

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/v1/notifications` | Create a notification (body: `CreateNotificationRequest` — userId, type, title, message, referenceId, referenceType) |
| GET | `/api/v1/notifications/user/{userId}` | List a user's notifications, paged & newest-first; optional `isRead`, `page`, `size` query params |
| GET | `/api/v1/notifications/user/{userId}/unread-count` | Return `{ "unreadCount": <n> }` for the user |
| PATCH | `/api/v1/notifications/{id}/read` | Mark a single notification read |
| PATCH | `/api/v1/notifications/user/{userId}/read-all` | Mark all of a user's notifications read |

`NotificationDto` exposes `id`, `userId`, `type`, `title`, `message`, `referenceId`, `referenceType`, `isRead`, `createdAt`.

## Data
- **`notifications`** (owned) — `Notification` entity: `user_id`, `type` (enum: CLAIM_STATUS_CHANGE, NEW_MESSAGE, LISTING_EXPIRY_WARNING, PAYOUT_RECEIVED, SYSTEM_ANNOUNCEMENT), `title`, `message`, `reference_id` + `reference_type` (soft link to the originating claim/listing/etc.), `is_read`, `created_at`.
- **`notification_settings`** (owned) — `NotificationSettings` entity: per-user channel toggles (email/push/sms), per-post & global subscription flags, delivery `frequency` (INSTANT / DIGEST / NONE) and digest hour.
- Both live in the shared `referral_marketplace` Postgres DB; `referenceId` values point at rows owned by other services (e.g. claims). See the [shared data model](./data-model.md). Flyway is disabled here (`flyway.enabled=false`) — this service does not own migrations; `ddl-auto` is `validate` locally / `update` in compose.

## Integrations
- **WebSocket / STOMP** — `spring-boot-starter-websocket`; `WebSocketConfig` registers a SockJS STOMP endpoint at `/ws/notifications` with an in-memory simple broker on `/topic` and `/queue`, app prefix `/app`, user prefix `/user`.
- **Email** — `EmailNotificationService` (Mailgun); gated by `mailgun.enabled` (default `false` → STUB logging in local dev).
- **Push** — `PushNotificationService` (Firebase Cloud Messaging); gated by `firebase.enabled` (default `false` → STUB in local dev).
- **SMS** — Twilio, currently a TODO stub in `NotificationService.sendSms`.
- **Scheduling** — `@Scheduled` hourly digest job flushes the in-memory digest queue for users whose configured hour matches.
- No Redis, no Feign clients; Resilience4j circuit breaker + Micrometer/OTel tracing are on the classpath.

## Inter-service
- **Reached via** the API gateway, which forwards requests after JWT validation. The internal `NotificationService` helper methods (`notifyTransactionStarted`, `notifyProofSubmitted`, `notifyPaymentPosted`, `notifyDisputeRaised`, etc.) are the intended fan-in points for other services (claim / payment flows) to raise notifications.
- **Calls out to**: the shared Postgres DB only. Email delivery has a TODO to fetch addresses from user-service (currently a stub); no live outbound service calls in local dev.

## Security
- The API gateway validates the JWT and injects the trusted `X-User-ID` (UUID), `X-User-Role`, and `X-User-Email` headers (stripping any client-supplied copies), so requests arriving here are already authenticated.
- `spring-boot-starter-security` and a `jwt.secret` are present, but this service ships no custom `SecurityConfig`/`GatewayIdentityFilter` (unlike admin-service/support-service); its endpoints key off the `{userId}` path variable / request body rather than reading `X-User-ID` directly. Current posture: authentication is enforced upstream at the gateway; tightening these handlers to bind to the gateway-injected `X-User-ID` is the natural next hardening step.

## Build & run
```
cd services/notification-service
./gradlew clean build      # compile + tests
./gradlew bootRun          # starts on port 8087
```

## Related
- [Vouch concept index](../index.md)
- [Shared data model](./data-model.md)
- [Claim Service](./service-claim.md)
- [Web frontend](./frontend-web.md)
