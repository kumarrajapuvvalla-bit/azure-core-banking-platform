# Postmortem: INC-002 — Service Bus DLQ Silent Accumulation

**Date:** Month 11 | **Severity:** P0 (retroactive) | **Duration:** 6 days undetected | **Status:** Resolved ✅

## Summary
Schema change added `paymentPurposeCode` field to payment messages. Ledger consumer not updated.
Every message threw JsonReaderException and went to Dead Letter Queue. No DLQ alert existed.
4,847 real customer transactions (standing orders, direct debits, salary payments) accumulated
unprocessed for 6 days. Customer balances incorrect. Discovered only during manual queue check.

## Timeline
| Time | Event |
|------|-------|
| Day 1, 09:14 | Payments team deploys schema update — new paymentPurposeCode field |
| Day 1, 09:15 | First ledger consumer failure — message moved to DLQ |
| Day 1–7 | 4,847 messages accumulate in DLQ silently — zero alerts |
| Day 7, 14:23 | Developer runs manual Service Bus Explorer check — discovers DLQ |
| Day 7, 15:05 | Patched consumer deployed — new failures stop |
| Day 7, 15:10 | DLQ reprocessing script run in batches of 50 |
| Day 7, 19:00 | All 4,847 messages reprocessed — balances corrected |

## Root Cause
- No monitoring on DLQ depth (primary)
- Schema change deployed without coordinated consumer update (contributing)
- No schema registry or API contract testing (contributing)

## Action Items
| Action | Status |
|--------|--------|
| Azure Monitor alert DLQ depth > 10 on ALL queues | ✅ Done |
| Grafana Service Bus dashboard | ✅ Done |
| Azure Event Grid Schema Registry | ✅ Done |
| Schema compatibility CI gate | ✅ Done |

## Lessons Learned
1. Infrastructure working correctly is not the same as the system working correctly.
   The DLQ worked exactly as designed. The gap was operational visibility.
2. Every async queue needs DLQ depth monitoring. Not optional.
3. Schema changes in event-driven systems need API contract enforcement at deploy time.
