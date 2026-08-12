# Database Migrations

## Overview

This directory contains the complete database schema for the Referral Marketplace platform.

---

## Migration Files

### V1__complete_schema.sql
**Complete database schema** for all 12 microservices.

#### Tables Created (12 total)

1. **users** - User accounts (Auth, User, Admin, Support services)
2. **devices** - Device fingerprinting (Auth Service)
3. **businesses** - Business entities (User Service)
4. **programs** - Referral programs (User Service)
5. **listings** - Referral listings (Listing Service)
6. **claims** - User claims (Claim Service, Admin, Support)
7. **evidence** - Claim evidence files (Claim Service)
8. **messages** - Claim chat messages (Claim Service, Support)
9. **ledger** - Financial transactions (Payment Service)
10. **notifications** - User notifications (Notification Service)
11. **audit_logs** - Audit trail (Audit Service, Admin)
12. **reviews** - User reviews (Future feature)

#### Indexes Created (50+)
- Performance-optimized indexes for all tables
- Composite indexes for common queries
- Partial indexes for filtered queries

#### Views Created (3)
- `listings_with_stats` - Listings with claim statistics
- `user_claim_stats` - User claim statistics
- `poster_listing_stats` - Poster listing statistics

#### Functions & Triggers (10)
- `update_updated_at_column()` - Auto-update timestamp
- Triggers on all tables with `updated_at` column

---

## Schema Design

### Shared Database Approach
All services share a single PostgreSQL database for the MVP. This can be split into separate databases per service in the future.

### Table Ownership
| Service | Primary Tables | Also Uses |
|---------|---------------|-----------|
| Auth Service | users, devices, audit_logs | - |
| User Service | businesses, programs | users |
| Listing Service | listings | users |
| Claim Service | claims, evidence, messages | users, listings |
| Payment Service | ledger | listings, claims |
| Admin Service | - | users, listings, claims, audit_logs |
| Support Service | - | users, claims, messages |
| Notification Service | notifications | users |
| Audit Service | audit_logs | users |

---

## Running Migrations

### Docker Compose (Automatic)
```bash
# Migrations run automatically on first startup
docker-compose up -d postgres

# Check migration status
docker exec -it referral-postgres psql -U referral_user -d referral_marketplace -c "\dt"
```

### Manual Migration
```bash
# Connect to database
psql -U referral_user -d referral_marketplace

# Run migration
\i migrations.sql/V1__complete_schema.sql

# Verify tables
\dt

# Verify indexes
\di

# Verify views
\dv
```

### Flyway Migration (Auth Service)
```bash
cd services/auth-service
./gradlew flywayMigrate
```

---

## Database Structure

### Entity Relationships

```
users
  ├─→ devices (one-to-many)
  ├─→ businesses (one-to-many)
  ├─→ listings (one-to-many as poster)
  ├─→ claims (one-to-many as seeker)
  ├─→ messages (one-to-many as sender)
  ├─→ notifications (one-to-many)
  └─→ reviews (one-to-many as reviewer/subject)

businesses
  └─→ programs (one-to-many)

listings
  ├─→ claims (one-to-many)
  └─→ ledger (one-to-many)

claims
  ├─→ evidence (one-to-many)
  ├─→ messages (one-to-many)
  ├─→ ledger (one-to-one for payout)
  └─→ reviews (one-to-one)
```

### Key Constraints

1. **Unique Constraints**
   - `users.email` - One email per user
   - `devices (user_id, device_id)` - One device per user
   - `businesses.website` - One website per business
   - `claims (listing_id, seeker_id)` - One claim per seeker per listing
   - `reviews.claim_id` - One review per claim

2. **Check Constraints**
   - User roles: poster, seeker, support, admin
   - Listing status: draft, active, expired, taken_down
   - Claim status: draft, submitted, under_review, approved, rejected, paid, disputed
   - Transaction types: escrow_hold, escrow_release, payout, refund, fee
   - Rating: 1-5 stars

3. **Foreign Key Constraints**
   - All child tables reference parent tables
   - Cascade deletes where appropriate
   - Set null on user deletion for audit logs

---

## Schema Statistics

### Table Sizes (Estimated for MVP)
- **users**: ~10,000 rows
- **devices**: ~30,000 rows (avg 3 devices per user)
- **businesses**: ~1,000 rows
- **programs**: ~5,000 rows
- **listings**: ~50,000 rows
- **claims**: ~100,000 rows
- **evidence**: ~200,000 rows (avg 2 per claim)
- **messages**: ~500,000 rows
- **ledger**: ~150,000 rows
- **notifications**: ~1,000,000 rows
- **audit_logs**: ~5,000,000 rows
- **reviews**: ~50,000 rows

### Performance Considerations
- All primary keys use UUID for global uniqueness
- Indexes on all foreign keys
- Composite indexes for common query patterns
- Partial indexes for filtered queries
- TIMESTAMPTZ for all timestamps (UTC)
- JSONB for flexible metadata storage

---

## Data Types

### Standardized Types
- **IDs**: UUID (globally unique)
- **Timestamps**: TIMESTAMPTZ (UTC timezone)
- **Money**: INTEGER (cents) or DECIMAL(10,2)
- **Enums**: VARCHAR with CHECK constraints
- **Metadata**: JSONB (flexible schema)
- **Text**: TEXT (unlimited length)

### Why These Choices?
- **UUID**: Better for distributed systems
- **TIMESTAMPTZ**: Handles timezones properly
- **INTEGER (cents)**: Avoids floating-point errors
- **JSONB**: Fast queries, flexible schema
- **CHECK constraints**: Database-level validation

---

## Migration Strategy

### Development
1. Drop and recreate database
2. Run V1__complete_schema.sql
3. Run seed data (optional)

### Staging/Production
1. Run Flyway migrations sequentially
2. Backup before each migration
3. Test migration on staging first
4. Use transactional migrations
5. Verify data integrity after migration

---

## Rollback Strategy

### V1 Rollback (if needed)
```sql
-- Drop all tables (CAUTION: Data loss!)
DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS ledger CASCADE;
DROP TABLE IF EXISTS messages CASCADE;
DROP TABLE IF EXISTS evidence CASCADE;
DROP TABLE IF EXISTS claims CASCADE;
DROP TABLE IF EXISTS listings CASCADE;
DROP TABLE IF EXISTS programs CASCADE;
DROP TABLE IF EXISTS businesses CASCADE;
DROP TABLE IF EXISTS devices CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Drop views
DROP VIEW IF EXISTS listings_with_stats;
DROP VIEW IF EXISTS user_claim_stats;
DROP VIEW IF EXISTS poster_listing_stats;

-- Drop function
DROP FUNCTION IF EXISTS update_updated_at_column();

-- Drop extension
DROP EXTENSION IF EXISTS "uuid-ossp";
```

---

## Verification

### Check Migration Success
```sql
-- Count tables
SELECT COUNT(*) FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
-- Expected: 12

-- Count indexes
SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';
-- Expected: 50+

-- Count views
SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'public';
-- Expected: 3

-- Check constraints
SELECT table_name, constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'public'
ORDER BY table_name;
```

### Sample Queries
```sql
-- Get all users with claim counts
SELECT * FROM user_claim_stats LIMIT 10;

-- Get all listings with statistics
SELECT * FROM listings_with_stats WHERE status = 'active' LIMIT 10;

-- Get escrow balance for a listing
SELECT 
    listing_id,
    SUM(CASE WHEN transaction_type = 'escrow_hold' AND status = 'completed' THEN amount_cents ELSE 0 END) -
    SUM(CASE WHEN transaction_type IN ('payout', 'refund') AND status = 'completed' THEN amount_cents ELSE 0 END) as balance_cents
FROM ledger
WHERE listing_id = '{uuid}'
GROUP BY listing_id;
```

---

## Database Access

### Connection Details
```
Host: localhost (dev) / postgres (docker)
Port: 5432
Database: referral_marketplace
Username: referral_user
Password: referral_password
```

### Connection String
```
postgresql://referral_user:referral_password@localhost:5432/referral_marketplace
```

### JDBC URL (for Spring Boot)
```
jdbc:postgresql://localhost:5432/referral_marketplace
```

---

## Maintenance

### Regular Tasks
1. **VACUUM**: Weekly (automated in PostgreSQL 15)
2. **ANALYZE**: After bulk inserts
3. **REINDEX**: Monthly on heavily used tables
4. **Backup**: Daily (automated via Docker volumes)

### Monitoring Queries
```sql
-- Check table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Check index usage
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Check slow queries
SELECT * FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

---

## Schema Version

- **Version**: 1.0
- **Created**: October 31, 2025
- **Last Updated**: October 31, 2025
- **Tables**: 12
- **Indexes**: 50+
- **Views**: 3
- **Triggers**: 10

---

## Migration Status

✅ **Complete database schema for all 12 services**
✅ **All tables, indexes, and relationships defined**
✅ **Views for common queries**
✅ **Triggers for automatic timestamp updates**
✅ **Sample data for development**
✅ **Comprehensive documentation**

**Status**: READY FOR USE 🚀

