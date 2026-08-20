#!/usr/bin/env bash
#
# purge-test-data.sh — one-shot removal of fake / QA / seed data from a Vouch
# environment's shared database.
#
# WHAT COUNTS AS TEST DATA
#   Everything anchored to a user whose email matches a test domain (default:
#   "example.com" — the QA seed domain, a reserved example TLD no real user can
#   own). That user plus ALL data they own or reference is removed, in
#   foreign-key-safe order:
#     users, their listings, transactions (evidence/messages/transaction_events
#     via cascade), reviews + review_grants, ledger rows for those
#     listings/transactions, businesses -> programs, devices, identity_* rows,
#     notifications, trust_profiles, matching email_outbox rows, and their
#     audit_logs.
#   flyway_schema_history is never touched.
#
# SAFETY
#   * DRY RUN by default: prints the row counts it WOULD delete and changes
#     nothing. You must pass --confirm (or CONFIRM=DELETE) to actually delete.
#   * All deletes run in a single transaction (all-or-nothing).
#   * Refuses to run with an empty/invalid test domain (which would match
#     everything).
#
# CONNECTION
#   By default the DB connection is read from the Kubernetes secret
#   ($DB_SECRET in namespace $KUBE_NAMESPACE, requires kubectl + KUBECONFIG).
#   Override entirely with PG_CONNINFO (a libpq conninfo string or URL), e.g.
#     PG_CONNINFO='host=... port=5432 dbname=... user=... sslmode=require'
#   (set PGPASSWORD too when using PG_CONNINFO without a password in it).
#
# USAGE
#   ./scripts/purge-test-data.sh                 # dry run (default)
#   ./scripts/purge-test-data.sh --confirm       # actually delete
#   TEST_EMAIL_DOMAINS="example.com,test.local" ./scripts/purge-test-data.sh --confirm
#   KUBE_NAMESPACE=referral DB_SECRET=referral-db ./scripts/purge-test-data.sh
#
set -euo pipefail

KUBE_NAMESPACE="${KUBE_NAMESPACE:-referral}"
DB_SECRET="${DB_SECRET:-referral-db}"
TEST_EMAIL_DOMAINS="${TEST_EMAIL_DOMAINS:-example.com}"

# --- confirmation -----------------------------------------------------------
CONFIRM="${CONFIRM:-}"
for arg in "$@"; do
  case "$arg" in
    --confirm) CONFIRM="DELETE" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done
DO_DELETE=0
[ "$CONFIRM" = "DELETE" ] && DO_DELETE=1

err() { echo "ERROR: $*" >&2; exit 1; }

b64dec() { base64 --decode 2>/dev/null || base64 -d; }

# --- build the email-domain predicates (validated to avoid SQL injection) ---
build_array() {
  # $1 = column expr. Emits: lower(<col>) LIKE ANY (ARRAY['%@dom1','%@dom2'])
  local col="$1" arr="" IFS=','
  read -ra doms <<< "$TEST_EMAIL_DOMAINS"
  for d in "${doms[@]}"; do
    d="$(echo "$d" | tr -d '[:space:]')"
    [ -z "$d" ] && continue
    [[ "$d" =~ ^[A-Za-z0-9.-]+$ ]] || err "Invalid test email domain: '$d' (allowed: letters, digits, '.', '-')"
    [ -n "$arr" ] && arr="$arr,"
    arr="$arr'%@$(echo "$d" | tr '[:upper:]' '[:lower:]')'"
  done
  [ -z "$arr" ] && err "TEST_EMAIL_DOMAINS is empty — refusing to run (would match nothing/everything)."
  echo "lower($col) LIKE ANY (ARRAY[$arr])"
}
EMAIL_PRED="$(build_array email)"
OUTBOX_PRED="$(build_array to_email)"

# --- resolve the DB connection ----------------------------------------------
if [ -n "${PG_CONNINFO:-}" ]; then
  CONN="$PG_CONNINFO"
  CONN_DESC="(from PG_CONNINFO)"
else
  command -v kubectl >/dev/null 2>&1 || err "kubectl not found and PG_CONNINFO not set."
  get() { kubectl -n "$KUBE_NAMESPACE" get secret "$DB_SECRET" -o jsonpath="{.data.$1}" 2>/dev/null | b64dec; }
  JDBC_URL="$(get SPRING_DATASOURCE_URL)"
  DB_USER="$(get SPRING_DATASOURCE_USERNAME)"
  DB_PASS="$(get SPRING_DATASOURCE_PASSWORD)"
  [ -n "$JDBC_URL" ] || err "Could not read SPRING_DATASOURCE_URL from secret $DB_SECRET in ns $KUBE_NAMESPACE."
  # Parse jdbc:postgresql://host[:port]/db[?params]
  rest="${JDBC_URL#jdbc:postgresql://}"
  hostport="${rest%%/*}"
  host="${hostport%%:*}"
  port="${hostport##*:}"; [ "$port" = "$hostport" ] && port=5432
  dbrest="${rest#*/}"; db="${dbrest%%\?*}"
  export PGPASSWORD="$DB_PASS"
  CONN="host=$host port=$port dbname=$db user=$DB_USER sslmode=require"
  CONN_DESC="host=$host db=$db user=$DB_USER (from secret $DB_SECRET)"
fi

command -v psql >/dev/null 2>&1 || err "psql (PostgreSQL client) not found."

echo "──────────────────────────────────────────────────────────────"
echo " Vouch — purge test data"
echo " target      : $CONN_DESC"
echo " test domains : $TEST_EMAIL_DOMAINS"
if [ "$DO_DELETE" -eq 1 ]; then
  echo " mode        : !!! DELETE (changes will be committed) !!!"
else
  echo " mode        : dry run (no changes; pass --confirm to delete)"
fi
echo "──────────────────────────────────────────────────────────────"

psql "$CONN" -v ON_ERROR_STOP=1 -v do_delete="$DO_DELETE" <<SQL
\set QUIET on
BEGIN;
CREATE TEMP TABLE _tu ON COMMIT DROP AS SELECT id FROM users WHERE $EMAIL_PRED;
CREATE TEMP TABLE _tl ON COMMIT DROP AS SELECT id FROM listings WHERE poster_id IN (SELECT id FROM _tu);
CREATE TEMP TABLE _tt ON COMMIT DROP AS
  SELECT id FROM transactions
  WHERE poster_id IN (SELECT id FROM _tu)
     OR seeker_id IN (SELECT id FROM _tu)
     OR listing_id IN (SELECT id FROM _tl);
\set QUIET off

\echo ''
\echo '=== Test rows matched ==='
SELECT 'users'        AS table_name, count(*) AS rows FROM _tu
UNION ALL SELECT 'listings',     count(*) FROM _tl
UNION ALL SELECT 'transactions', count(*) FROM _tt
UNION ALL SELECT 'businesses',   count(*) FROM businesses WHERE owner_id IN (SELECT id FROM _tu)
UNION ALL SELECT 'reviews',      count(*) FROM reviews
             WHERE reviewer_id IN (SELECT id FROM _tu)
                OR reviewee_id IN (SELECT id FROM _tu)
                OR transaction_id IN (SELECT id FROM _tt)
UNION ALL SELECT 'email_outbox', count(*) FROM email_outbox WHERE $OUTBOX_PRED
UNION ALL SELECT 'audit_logs',   count(*) FROM audit_logs WHERE actor_id IN (SELECT id FROM _tu)
ORDER BY table_name;

\if :do_delete
  \echo ''
  \echo '=== Deleting (single transaction) ==='
  DELETE FROM ledger WHERE listing_id IN (SELECT id FROM _tl) OR claim_id IN (SELECT id FROM _tt);
  DELETE FROM reviews
    WHERE reviewer_id IN (SELECT id FROM _tu)
       OR reviewee_id IN (SELECT id FROM _tu)
       OR transaction_id IN (SELECT id FROM _tt)
       OR grant_id IN (SELECT id FROM review_grants WHERE transaction_id IN (SELECT id FROM _tt));
  DELETE FROM review_grants WHERE transaction_id IN (SELECT id FROM _tt);
  DELETE FROM transactions WHERE id IN (SELECT id FROM _tt);
  DELETE FROM listings WHERE id IN (SELECT id FROM _tl);
  DELETE FROM email_outbox WHERE $OUTBOX_PRED;
  DELETE FROM audit_logs WHERE actor_id IN (SELECT id FROM _tu);
  UPDATE users SET merged_into_user_id = NULL WHERE merged_into_user_id IN (SELECT id FROM _tu);
  DELETE FROM users WHERE id IN (SELECT id FROM _tu);
  COMMIT;
  \echo ''
  \echo 'Done. Remaining test users (should be 0):'
  SELECT count(*) AS remaining_test_users FROM users WHERE $EMAIL_PRED;
\else
  ROLLBACK;
  \echo ''
  \echo 'DRY RUN — nothing was deleted. Re-run with --confirm (or CONFIRM=DELETE) to apply.'
\endif
SQL

echo "──────────────────────────────────────────────────────────────"
if [ "$DO_DELETE" -eq 1 ]; then
  echo " Purge complete."
else
  echo " Dry run complete. No data was changed."
fi
