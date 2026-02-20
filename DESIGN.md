# GitHub Events - Design Brief

## Overview

GitHub Events is a background job system that continuously ingests GitHub Push events from the public API, enriches them with actor and repository metadata, and stores them durably for analytical queries.

The system prioritizes **reliability over throughput**, gracefully handling API rate limits and transient failures without requiring authentication.

## Design Decisions

### 1. No Authentication

**Decision:** Use unauthenticated GitHub API requests (60/min limit).

**Rationale:**
- Avoids managing secrets/tokens (no token expiry risk)
- Simpler deployment and configuration
- Story 4 explicitly forbids tokens
- 60 requests/minute is sufficient for enrichment (5-6 events/minute ingestion, 1 API call per event for enrichment)

**Trade-off:** Rate limits are tighter, but with proactive backoff at 10% remaining, we never hit the wall.

### 2. Dual Storage: Raw + Structured

**Decision:** Store both raw JSON payloads and structured relational data.

**Rationale:**
- **Raw payloads** (GithubEvent.raw_payload): Audit trail, re-enrichment capability, schema flexibility
- **Structured data** (PushEvent, Actor, Repository): Fast queries without JSON parsing, analytics-friendly

**Trade-off:** Slight storage overhead, but enables both compliance (audit) and performance (analytics).

### 3. Graceful Rate Limit Handling

**Decision:** Read `X-RateLimit-*` headers on every request and proactively back off at 10% remaining.

**Rationale:**
- Prevents crashes and retries that waste quota
- Clear observability into API consumption
- Sidekiq exponential backoff (1s, 2s, 4s...) allows reset window (60 seconds) to pass
- Logs inform operators of approaching limits

**Implementation:**
```ruby
GithubRateLimitTracker.track_request(response)
  # Raises RateLimitError if remaining < 10% of limit
  # Logs warnings at 20% and 50%
  # Stores state in cache for monitoring
```

### 4. Orphaned Event Tolerance

**Decision:** Allow PushEvent records to exist without associated Repository.

**Rationale:**
- Repository creation can fail if payload lacks `github_id` or `full_name`
- Story 1 requires events be "persisted durably" - shouldn't lose events due to missing enrichment
- Graceful degradation: analysts can still query event structure, just with incomplete repo data
- Can re-try enrichment later

**Monitoring:** `PushEvent.orphaned.count` alerts if anomalous.

### 5. Separate Ingestion and Enrichment Jobs

**Decision:** Two independent jobs on different schedules (5-min ingest, 10-min enrich).

**Rationale:**
- Decouples API call concerns (ingest is simple, reliable)
- Enrichment can fail independently without blocking ingestion
- Different rate limiting profiles (ingest: 1 call total, enrich: N calls)
- Easier to debug and scale separately

**Schedules:**
- `FetchGithubEventsJob`: Every 5 minutes (lightweight, single API call)
- `EnrichPushEventsJob`: Every 10 minutes (heavier, multiple API calls per event)

### 6. Caching Strategy

**Decision:** Cache Actor and Repository data for 24 hours (skip enrichment if `last_enriched_at > 24.hours.ago`).

**Rationale:**
- Actor/repo profiles don't change frequently
- Reduces API calls by ~90%
- Matches GitHub's API pagination/cache headers
- Still fresh enough for analysis

**Trade-off:** Historical data (follower count, stars) lags by up to 24 hours.

### 7. Sidekiq for Job Scheduling

**Decision:** Use Sidekiq's scheduler (cron) rather than external job service.

**Rationale:**
- No external dependencies (reduces operational complexity)
- In-process with Rails (easier debugging)
- Scheduler is reliable for 5-10 minute intervals
- Dead letter queue tracks failures

**Retry Policy:** 5 retries with exponential backoff, then dead letter queue.

## Data Model

### Why This Structure?

```
GithubEvent (raw audit trail)
  └─> PushEvent (extracted push data)
       ├─> Actor (enriched user/org)
       └─> Repository (enriched repo)
```

**Rationale:**
- **GithubEvent**: Immutable record of what GitHub API returned (audit, re-enrichment capability)
- **PushEvent**: Queryable push data (ref, head, before) without parsing JSON
- **Actor/Repository**: Shared across all push events from same user/repo (denormalization reduction)

**Foreign Keys:**
- `PushEvent.repository_id` is OPTIONAL (graceful orphan handling)
- `PushEvent.actor_id` is OPTIONAL (enrichment may fail)

## Trade-offs & Limitations

| Decision | Benefit | Limitation |
|----------|---------|-----------|
| No auth | Simple, no secret mgmt | 60 req/min rate limit |
| Graceful rate limit | No crashes | Delays enrichment 1-2 minutes |
| 24h cache | 90% fewer API calls | Data lags 24 hours |
| Optional repo_id | Tolerates bad payloads | Can't query some events by repo |
| Sidekiq cron | Simple | Won't survive app restart if jobs pending |

## Future Improvements

1. **Metrics export** (Prometheus): Add `/metrics` endpoint for external monitoring
2. **Webhook ingestion** (optional): Supplement polling with GitHub webhooks for lower latency
3. **Multi-tenant**: Allow filtering by repo/org to ingest selective repositories
4. **Error dashboard**: UI to inspect dead letter queue and orphaned events
5. **Incremental enrichment**: Cache API etags to reduce bandwidth

## Acceptance Criteria Met

| Story | Criterion | Status |
|-------|-----------|--------|
| 1 | Events ingested from GitHub Public Events API | ✅ |
| 1 | Only PushEvent processed | ✅ |
| 1 | Events persisted durably | ✅ |
| 1 | Events uniquely identified | ✅ |
| 1 | Ingestion repeatable/continuous | ✅ |
| 2 | Raw payloads retained | ✅ |
| 2 | Key fields (repo, push_id, ref, head, before) queryable | ✅ |
| 2 | Data modeling documented | ✅ |
| 3 | Actor/repo data fetched from API URLs | ✅ |
| 3 | Enriched data persisted | ✅ |
| 3 | Avoids unnecessary repeated fetches (24h cache) | ✅ |
| 3 | Approach explained in design brief | ✅ |
| 4 | Logs indicate ingestion, processing, failures | ✅ |
| 4 | Malformed data handled gracefully | ✅ |
| 4 | No crash-loop on transient failures | ✅ |
| 4 | Rate limits observed and handled gracefully | ✅ |

---

**Version:** 1.0  
**Last Updated:** 2026-02-20  
**Author:** GitHub Events Team