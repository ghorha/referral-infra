-- ============================================================================
-- REFERRAL MARKETPLACE - COMPLETE DATABASE SCHEMA
-- ============================================================================
-- This migration creates all tables for all microservices.
-- Version: 2.0  (consolidated to the "transactions" model — no-escrow, reputation-enforced)
-- ============================================================================
-- NOTE: The deal entity was consolidated from `claims` to `transactions`. claim-service owns
-- the rich model (state machine, event log, trust profiles); admin/listing/support read the
-- legacy shape through the `claims` compatibility VIEW defined near the bottom of this file.
-- See docs/design/reputation-state-machine.md.
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For text search

-- ============================================================================
-- USER MANAGEMENT TABLES (Auth Service, User Service)
-- ============================================================================

-- Users table (Core user data)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    display_name VARCHAR(255),
    phone_number VARCHAR(50),
    profile_image_url VARCHAR(1000),
    role VARCHAR(20) NOT NULL DEFAULT 'poster' CHECK (role IN ('poster', 'seeker', 'support', 'admin')),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended', 'deleted')),
    bio TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Devices table (Device fingerprinting)
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255) NOT NULL,
    fingerprint_hash VARCHAR(255) NOT NULL,
    device_name VARCHAR(255),
    device_type VARCHAR(50) CHECK (device_type IN ('desktop', 'mobile', 'tablet', 'unknown')),
    user_agent TEXT,
    ip_address INET,
    first_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_trusted BOOLEAN DEFAULT false,
    is_blocked BOOLEAN DEFAULT false,
    blocked_reason TEXT,
    blocked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_user_device UNIQUE (user_id, device_id)
);

-- Businesses table (User Service)
CREATE TABLE businesses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    website VARCHAR(500) NOT NULL UNIQUE,
    industry VARCHAR(100),
    location VARCHAR(255),
    logo_url VARCHAR(1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Programs table (User Service)
CREATE TABLE programs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'paused', 'inactive')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- LISTING TABLES (Listing Service)
-- ============================================================================

-- Listings table
CREATE TABLE listings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    poster_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reward_amount DECIMAL(10, 2) NOT NULL CHECK (reward_amount > 0),
    max_claims INTEGER NOT NULL DEFAULT 100 CHECK (max_claims > 0),
    time_period_days INTEGER NOT NULL CHECK (time_period_days > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'expired', 'taken_down')),
    expiry_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- TRANSACTION TABLES (Claim Service) — the deal between a poster and a seeker
-- ============================================================================

-- Transactions table (formerly `claims`). Rich model owned by claim-service.
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
    poster_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    seeker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL DEFAULT 'STARTED',

    -- Settlement (no-escrow model)
    settlement_mode VARCHAR(30) NOT NULL DEFAULT 'OFF_PLATFORM_ATTESTED',
    split_terms JSONB,
    state_owner VARCHAR(20),
    sla_deadline TIMESTAMPTZ,

    -- Timeline
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    waiting_for_proof_since TIMESTAMPTZ,
    proof_submitted_at TIMESTAMPTZ,
    proof_approved_at TIMESTAMPTZ,
    waiting_for_payment_since TIMESTAMPTZ,
    poster_received_at TIMESTAMPTZ,
    escrowed_at TIMESTAMPTZ,
    payout_initiated_at TIMESTAMPTZ,
    payout_confirmed_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '45 days'),

    -- Money
    promised_amount_cents INTEGER,
    platform_fee_cents INTEGER,
    seeker_receives_cents INTEGER,
    poster_original_reward_cents INTEGER,

    -- Proof (seeker)
    seeker_proof_urls JSONB,
    seeker_proof_description TEXT,
    seeker_proof_ocr_text TEXT,
    seeker_proof_ocr_confidence DOUBLE PRECISION,

    -- Proof (poster)
    poster_proof_urls JSONB,
    poster_proof_description TEXT,
    poster_proof_ocr_text TEXT,

    -- Dispute
    dispute_raised_at TIMESTAMPTZ,
    dispute_raised_by UUID REFERENCES users(id) ON DELETE SET NULL,
    dispute_reason TEXT,
    dispute_evidence_urls JSONB,
    dispute_resolved_at TIMESTAMPTZ,
    dispute_resolution TEXT,
    dispute_resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Messaging
    last_message_at TIMESTAMPTZ,
    unread_messages_poster INTEGER NOT NULL DEFAULT 0,
    unread_messages_seeker INTEGER NOT NULL DEFAULT 0,

    -- Payment references (retained for the no-escrow attestation record)
    stripe_payment_id VARCHAR(255),
    stripe_payout_id VARCHAR(255),
    estimated_arrival_date TIMESTAMPTZ,
    case_open BOOLEAN NOT NULL DEFAULT false,

    -- Free-text note + reward amount, shared with the admin/support read models.
    notes TEXT,
    reward_amount DECIMAL(10, 2),

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT unique_listing_seeker UNIQUE (listing_id, seeker_id),
    CONSTRAINT valid_transaction_status CHECK (status IN (
        'STARTED', 'WAITING_FOR_SEEKER_PROOF', 'PROOF_SUBMITTED_IN_REVIEW',
        'WAITING_FOR_POSTER_PAYMENT', 'POSTER_REWARDED', 'PAYOUT_SENT', 'PAYOUT_CONFIRMED',
        'TRANSACTION_CLOSED', 'NOT_QUALIFIED', 'CLAWED_BACK', 'COMPLETED_UNCONFIRMED',
        'DISPUTED', 'CANCELLED')),
    CONSTRAINT valid_settlement_mode CHECK (settlement_mode IN ('MERCHANT_NATIVE', 'OFF_PLATFORM_ATTESTED'))
);

-- Append-only lifecycle event log (source of truth for "what and where")
CREATE TABLE transaction_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    from_state VARCHAR(50),
    to_state VARCHAR(50) NOT NULL,
    event VARCHAR(80) NOT NULL,
    actor VARCHAR(20) NOT NULL,
    skill_verdict JSONB,
    payload JSONB,
    trace_id VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Evidence table
CREATE TABLE evidence (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    file_url VARCHAR(1000) NOT NULL,
    file_type VARCHAR(50) NOT NULL,
    file_size_bytes INTEGER NOT NULL,
    ocr_data JSONB,
    verification_status VARCHAR(20) DEFAULT 'PENDING' CHECK (verification_status IN ('PENDING', 'VERIFIED', 'FAILED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Messages table (per-transaction chat/messaging)
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- REPUTATION TABLES (Claim Service) — the enforcement lever in the no-escrow model
-- ============================================================================

CREATE TABLE trust_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    score NUMERIC NOT NULL DEFAULT 0,
    tier VARCHAR(20) NOT NULL DEFAULT 'NEW',
    verification_level INTEGER NOT NULL DEFAULT 0,
    max_deal_value_cents BIGINT NOT NULL DEFAULT 2000,
    deals_completed INTEGER NOT NULL DEFAULT 0,
    disputes_lost INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT valid_trust_tier CHECK (tier IN ('NEW', 'BRONZE', 'SILVER', 'GOLD'))
);

-- ============================================================================
-- PAYMENT TABLES (Payment Service)
-- ============================================================================

-- Ledger table (all financial transactions). `claim_id` retained as the column name for
-- payment-service back-compat; it now references transactions(id).
CREATE TABLE ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID REFERENCES listings(id) ON DELETE SET NULL,
    claim_id UUID REFERENCES transactions(id) ON DELETE SET NULL,
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('escrow_hold', 'escrow_release', 'payout', 'refund', 'fee')),
    amount_cents INTEGER NOT NULL,
    stripe_payment_intent_id VARCHAR(255),
    stripe_payout_id VARCHAR(255),
    webhook_event_id VARCHAR(255) UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
    metadata JSONB,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- NOTIFICATION TABLES (Notification Service)
-- ============================================================================

-- Notifications table
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL CHECK (type IN ('claim_status_change', 'new_message', 'listing_expiry_warning', 'payout_received', 'system_announcement')),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    reference_id UUID,
    reference_type VARCHAR(50),
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- AUDIT TABLES (Audit Service, Admin Service)
-- ============================================================================

-- Audit logs table
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
    trace_id VARCHAR(255) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
    actor_type VARCHAR(50),
    target_type VARCHAR(50),
    target_id UUID,
    action VARCHAR(50) NOT NULL,
    resource VARCHAR(100),
    changes JSONB,
    result VARCHAR(20) NOT NULL CHECK (result IN ('success', 'failure', 'error')),
    ip_address INET,
    user_agent TEXT,
    metadata JSONB,
    deleted_at TIMESTAMPTZ
);

-- ============================================================================
-- REVIEW TABLES (Claim Service) — three-way, double-blind, weighted reviews
-- ============================================================================

CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    reviewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reviewee_id UUID REFERENCES users(id) ON DELETE SET NULL,
    target_type VARCHAR(20) NOT NULL CHECK (target_type IN ('POSTER_PERSON', 'SEEKER_PERSON', 'POST')),
    target_id UUID NOT NULL,
    overall_rating INTEGER NOT NULL CHECK (overall_rating >= 1 AND overall_rating <= 5),
    review_text TEXT NOT NULL,
    response_time_rating INTEGER,
    communication_rating INTEGER,
    reliability_rating INTEGER,
    payment_speed_rating INTEGER,
    timeline_accuracy_rating INTEGER,
    instructions_clarity_rating INTEGER,
    actual_timeline_days INTEGER,
    would_recommend BOOLEAN,
    helpful_count INTEGER NOT NULL DEFAULT 0,
    not_helpful_count INTEGER NOT NULL DEFAULT 0,
    response_text TEXT,
    response_at TIMESTAMPTZ,
    -- Reputation signals (double-blind, weighted)
    outcome VARCHAR(30),
    reveal_at TIMESTAMPTZ,
    weight NUMERIC,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT one_review_per_transaction_target UNIQUE (transaction_id, reviewer_id, target_type),
    CONSTRAINT valid_review_outcome CHECK (outcome IS NULL OR outcome IN (
        'PAID_ON_TIME', 'PAID_LATE', 'NOT_PAID', 'MERCHANT_CLAWBACK', 'SEEKER_NO_QUALIFY', 'GHOSTED'))
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Users indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_created_at ON users(created_at DESC);

-- Devices indexes
CREATE INDEX idx_devices_user ON devices(user_id);
CREATE INDEX idx_devices_device_id ON devices(device_id);
CREATE INDEX idx_devices_fingerprint ON devices(fingerprint_hash);
CREATE INDEX idx_devices_last_seen ON devices(last_seen DESC);
CREATE INDEX idx_devices_is_blocked ON devices(is_blocked);
CREATE INDEX idx_devices_is_trusted ON devices(is_trusted);

-- Businesses indexes
CREATE INDEX idx_businesses_owner ON businesses(owner_id);
CREATE INDEX idx_businesses_name ON businesses(name);
CREATE INDEX idx_businesses_industry ON businesses(industry);

-- Programs indexes
CREATE INDEX idx_programs_business ON programs(business_id);
CREATE INDEX idx_programs_status ON programs(status);

-- Listings indexes
CREATE INDEX idx_listings_poster ON listings(poster_id);
CREATE INDEX idx_listings_status ON listings(status);
CREATE INDEX idx_listings_expiry_at ON listings(expiry_at);
CREATE INDEX idx_listings_created_at ON listings(created_at DESC);

-- Transactions indexes
CREATE INDEX idx_transactions_listing ON transactions(listing_id);
CREATE INDEX idx_transactions_poster ON transactions(poster_id);
CREATE INDEX idx_transactions_seeker ON transactions(seeker_id);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_settlement_mode ON transactions(settlement_mode);
CREATE INDEX idx_transactions_sla_deadline ON transactions(sla_deadline) WHERE sla_deadline IS NOT NULL;
CREATE INDEX idx_transactions_expires_at ON transactions(expires_at);
CREATE INDEX idx_transactions_started_at ON transactions(started_at DESC);

-- Transaction events indexes
CREATE INDEX idx_transaction_events_txn ON transaction_events(transaction_id, created_at);

-- Evidence indexes
CREATE INDEX idx_evidence_transaction ON evidence(transaction_id);
CREATE INDEX idx_evidence_verification_status ON evidence(verification_status);
CREATE INDEX idx_evidence_created_at ON evidence(created_at DESC);

-- Messages indexes
CREATE INDEX idx_messages_transaction ON messages(transaction_id);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_created_at ON messages(created_at ASC);

-- Ledger indexes
CREATE INDEX idx_ledger_listing ON ledger(listing_id);
CREATE INDEX idx_ledger_claim ON ledger(claim_id);
CREATE INDEX idx_ledger_transaction_type ON ledger(transaction_type);
CREATE INDEX idx_ledger_status ON ledger(status);
CREATE INDEX idx_ledger_created_at ON ledger(created_at DESC);

-- Notifications indexes
CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_notifications_type ON notifications(type);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);
CREATE INDEX idx_notifications_user_unread ON notifications(user_id, is_read) WHERE is_read = false;

-- Audit logs indexes
CREATE INDEX idx_audit_logs_trace_id ON audit_logs(trace_id);
CREATE INDEX idx_audit_logs_event_type ON audit_logs(event_type);
CREATE INDEX idx_audit_logs_actor_id ON audit_logs(actor_id);
CREATE INDEX idx_audit_logs_target_id ON audit_logs(target_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX idx_audit_logs_result ON audit_logs(result);

-- Reviews indexes
CREATE INDEX idx_reviews_transaction ON reviews(transaction_id);
CREATE INDEX idx_reviews_reviewee ON reviews(reviewee_id);
CREATE INDEX idx_reviews_reviewer ON reviews(reviewer_id);
CREATE INDEX idx_reviews_overall_rating ON reviews(overall_rating);

-- ============================================================================
-- FUNCTIONS AND TRIGGERS
-- ============================================================================

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for updated_at columns
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_devices_updated_at BEFORE UPDATE ON devices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_businesses_updated_at BEFORE UPDATE ON businesses
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_programs_updated_at BEFORE UPDATE ON programs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_listings_updated_at BEFORE UPDATE ON listings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_evidence_updated_at BEFORE UPDATE ON evidence
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_messages_updated_at BEFORE UPDATE ON messages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_trust_profiles_updated_at BEFORE UPDATE ON trust_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_ledger_updated_at BEFORE UPDATE ON ledger
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_reviews_updated_at BEFORE UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View for listing with transaction count
CREATE OR REPLACE VIEW listings_with_stats AS
SELECT
    l.*,
    COUNT(t.id) as total_claims,
    COUNT(CASE WHEN t.status = 'POSTER_REWARDED' THEN 1 END) as approved_claims,
    COUNT(CASE WHEN t.status = 'TRANSACTION_CLOSED' THEN 1 END) as paid_claims,
    COALESCE(SUM(CASE WHEN le.transaction_type = 'escrow_hold' AND le.status = 'completed' THEN le.amount_cents ELSE 0 END), 0) as total_escrowed_cents,
    COALESCE(SUM(CASE WHEN le.transaction_type = 'payout' AND le.status = 'completed' THEN le.amount_cents ELSE 0 END), 0) as total_paid_out_cents
FROM listings l
LEFT JOIN transactions t ON l.id = t.listing_id
LEFT JOIN ledger le ON l.id = le.listing_id
GROUP BY l.id;

-- View for user transaction statistics
CREATE OR REPLACE VIEW user_claim_stats AS
SELECT
    u.id as user_id,
    u.email,
    u.display_name,
    COUNT(DISTINCT t.id) as total_claims,
    COUNT(DISTINCT CASE WHEN t.status = 'POSTER_REWARDED' THEN t.id END) as approved_claims,
    COUNT(DISTINCT CASE WHEN t.status = 'TRANSACTION_CLOSED' THEN t.id END) as paid_claims,
    COALESCE(SUM(CASE WHEN t.status = 'TRANSACTION_CLOSED' THEN t.reward_amount ELSE 0 END), 0) as total_earnings
FROM users u
LEFT JOIN transactions t ON u.id = t.seeker_id
GROUP BY u.id, u.email, u.display_name;

-- View for listing poster statistics
CREATE OR REPLACE VIEW poster_listing_stats AS
SELECT
    u.id as user_id,
    u.email,
    u.display_name,
    COUNT(DISTINCT l.id) as total_listings,
    COUNT(DISTINCT CASE WHEN l.status = 'active' THEN l.id END) as active_listings,
    COUNT(DISTINCT t.id) as total_claims_received,
    COUNT(DISTINCT CASE WHEN t.status = 'TRANSACTION_CLOSED' THEN t.id END) as paid_claims
FROM users u
LEFT JOIN listings l ON u.id = l.poster_id
LEFT JOIN transactions t ON l.id = t.listing_id
GROUP BY u.id, u.email, u.display_name;

-- ============================================================================
-- SAMPLE DATA (Optional - for development)
-- ============================================================================

-- Insert sample admin user (password: will be set via magic link)
INSERT INTO users (email, display_name, role, status)
VALUES
    ('admin@referralmarketplace.com', 'System Admin', 'admin', 'active'),
    ('support@referralmarketplace.com', 'Support Team', 'support', 'active')
ON CONFLICT (email) DO NOTHING;

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE users IS 'Core user accounts for the platform';
COMMENT ON TABLE devices IS 'Device fingerprinting for security and UX';
COMMENT ON TABLE businesses IS 'Business entities that create referral programs';
COMMENT ON TABLE programs IS 'Referral programs created by businesses';
COMMENT ON TABLE listings IS 'Individual referral listings within programs';
COMMENT ON TABLE transactions IS 'Peer-to-peer referral deals between posters and seekers (formerly claims)';
COMMENT ON TABLE transaction_events IS 'Append-only lifecycle event log for each transaction';
COMMENT ON TABLE trust_profiles IS 'Per-user reputation profile (no-escrow enforcement lever)';
COMMENT ON TABLE evidence IS 'Evidence files uploaded to support a transaction';
COMMENT ON TABLE messages IS 'Chat messages within a transaction conversation';
COMMENT ON TABLE ledger IS 'Financial transaction ledger (settlement record; no custody)';
COMMENT ON TABLE notifications IS 'User notifications for various events';
COMMENT ON TABLE audit_logs IS 'Comprehensive audit trail for all actions';
COMMENT ON TABLE reviews IS 'Three-way, double-blind, weighted reviews after a transaction closes';

COMMENT ON COLUMN transactions.status IS 'Referral-split lifecycle (see docs/design/reputation-state-machine.md)';
COMMENT ON COLUMN transactions.settlement_mode IS 'MERCHANT_NATIVE (merchant settles the split atomically) or OFF_PLATFORM_ATTESTED (peer-to-peer)';

-- ============================================================================
-- STATISTICS UPDATE
-- ============================================================================

ANALYZE users;
ANALYZE devices;
ANALYZE businesses;
ANALYZE programs;
ANALYZE listings;
ANALYZE transactions;
ANALYZE transaction_events;
ANALYZE trust_profiles;
ANALYZE evidence;
ANALYZE messages;
ANALYZE ledger;
ANALYZE notifications;
ANALYZE audit_logs;
ANALYZE reviews;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Database schema migration completed successfully (transactions model)';
END $$;
