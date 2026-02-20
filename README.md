# GitHub Events

A robust data ingestion system that processes GitHub Push events from the Public Events API, enriches them with actor and repository metadata, and stores them durably for analysis.

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Ruby 3.2.3
- PostgreSQL 15+

### Setup

```bash
# Clone the repository
git clone https://github.com/jonpstone/github_events.git
cd github_events

# Start services
docker-compose up -d

# Run migrations
docker-compose exec web bundle exec rails db:migrate

# Start background jobs
docker-compose exec sidekiq bundle exec sidekiq -c 5 -v
```

Visit http://localhost:3000 for the Rails server.
Visit http://localhost:6379 for Redis (Sidekiq queue backend).

### Environment Variables

Create a `.env` file in the root directory:

```
# Database
DATABASE_HOST=postgres
POSTGRES_USER=postgres
POSTGRES_PASSWORD=password
RAILS_MAX_THREADS=5

# Rails
RAILS_ENV=development
RAILS_LOG_TO_STDOUT=true

# Sidekiq
REDIS_URL=redis://redis:6379/0
```

## Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────┐
│                   GitHub Public Events API              │
│                  (60 requests/minute, public)           │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
        ┌────────────────────────────────┐
        │   FetchGithubEventsJob         │
        │   (runs every 5 minutes)       │
        │   - Fetches events from API    │
        │   - Filters for PushEvent type │
        │   - Stores raw payloads        │
        └────────┬───────────────────────┘
                 │
                 ▼
        ┌────────────────────────────────┐
        │       GithubEvent Model        │
        │   (raw_payload stored as JSON) │
        │   (triggers PushEvent creation)│
        └────────┬───────────────────────┘
                 │
                 ▼
        ┌────────────────────────────────┐
        │       PushEvent Model          │
        │   - ref, head, before          │
        │   - repository_id (optional)   │
        │   - actor_id (optional)        │
        │   - enriched_at timestamp      │
        └────────┬───────────────────────┘
                 │
                 ▼
        ┌────────────────────────────────┐
        │   EnrichPushEventsJob          │
        │   (runs every 10 minutes)      │
        │   - Fetches Actor metadata     │
        │   - Fetches Repository metadata│
        │   - Updates PushEvent records  │
        └────────┬───────────────────────┘
                 │
         ┌───────┴────────┐
         ▼                ▼
    ┌─────────┐      ┌────────────┐
    │  Actor  │      │ Repository │
    │  Model  │      │   Model    │
    └─────────┘      └────────────┘
         │                │
         └────────┬───────┘
                  ▼
        ┌──────────────────────┐
        │   PostgreSQL DB      │
        │   (durable storage)  │
        └──────────────────────┘
```

### Data Flow

1. **Ingestion (every 5 minutes)**
   - `FetchGithubEventsJob` calls GitHub Public Events API
   - Unauthenticated requests (60/min rate limit)
   - Filters for `PushEvent` type only
   - Creates `GithubEvent` record with raw payload
   - Triggers `PushEvent` creation from payload
   - Enqueues `EnrichPushEventsJob`

2. **Enrichment (every 10 minutes)**
   - `EnrichPushEventsJob` finds unenriched `PushEvent` records
   - For each event, `EnrichPushEventService`:
     - Creates/fetches `Actor` from payload
     - Fetches detailed actor data from GitHub API if needed
     - Creates/fetches `Repository` from payload
     - Fetches detailed repository data from GitHub API if needed
     - Tracks rate limit using `GithubRateLimitTracker`
     - Marks events as enriched with `enriched_at` timestamp
   - Gracefully handles failures, rate limits, and orphaned records

3. **Storage**
   - Raw payloads retained in `GithubEvent.raw_payload` (audit trail)
   - Structured data in `PushEvent`, `Actor`, `Repository` tables
   - Queryable without parsing JSON

### Job Scheduling

Jobs are scheduled via Sidekiq using `config/sidekiq.yml`:

```yaml
fetch_github_events:
  cron: '*/5 * * * *'  # Every 5 minutes
  class: FetchGithubEventsJob

enrich_push_events:
  cron: '*/10 * * * *' # Every 10 minutes
  class: EnrichPushEventsJob
```

## Data Models

### GithubEvent
Stores raw API responses as audit trail.

```sql
CREATE TABLE github_events (
  id BIGINT PRIMARY KEY,
  event_id VARCHAR UNIQUE NOT NULL,
  event_type VARCHAR NOT NULL,
  actor_login VARCHAR,
  actor_avatar_url VARCHAR,
  repo_name VARCHAR,
  repo_id BIGINT,
  raw_payload JSONB NOT NULL,
  payload JSONB,
  github_created_at TIMESTAMP
);
```

### PushEvent
Structured push event data, queryable without JSON parsing.

```sql
CREATE TABLE push_events (
  id BIGINT PRIMARY KEY,
  github_event_id BIGINT UNIQUE NOT NULL,
  repository_id BIGINT,
  actor_id BIGINT,
  push_id VARCHAR,
  ref VARCHAR NOT NULL,
  head VARCHAR NOT NULL,
  before VARCHAR NOT NULL,
  enriched_at TIMESTAMP,
  created_at TIMESTAMP,
  FOREIGN KEY (github_event_id) REFERENCES github_events(id),
  FOREIGN KEY (repository_id) REFERENCES repositories(id),
  FOREIGN KEY (actor_id) REFERENCES actors(id)
);
```

### Actor
GitHub user/organization metadata.

```sql
CREATE TABLE actors (
  id BIGINT PRIMARY KEY,
  github_id BIGINT UNIQUE NOT NULL,
  login VARCHAR NOT NULL,
  avatar_url VARCHAR,
  profile_url VARCHAR,
  actor_type VARCHAR,
  name VARCHAR,
  bio VARCHAR,
  company VARCHAR,
  location VARCHAR,
  followers INTEGER,
  following INTEGER,
  public_repos INTEGER,
  last_enriched_at TIMESTAMP,
  failed_attempts INTEGER DEFAULT 0
);
```

### Repository
Repository metadata.

```sql
CREATE TABLE repositories (
  id BIGINT PRIMARY KEY,
  github_id BIGINT UNIQUE NOT NULL,
  full_name VARCHAR NOT NULL,
  name VARCHAR,
  description TEXT,
  language VARCHAR,
  repository_url VARCHAR,
  clone_url VARCHAR,
  default_branch VARCHAR,
  stars_count INTEGER,
  forks_count INTEGER,
  watchers_count INTEGER,
  homepage VARCHAR,
  topics TEXT[],
  is_fork BOOLEAN,
  is_private BOOLEAN,
  license VARCHAR,
  last_enriched_at TIMESTAMP,
  failed_attempts INTEGER DEFAULT 0
);
```

## Monitoring & Observability

### Logs

All logs include structured data (JSON) for easy parsing and aggregation:

```json
{"event":"fetch_github_events_completed","total_events":30,"newly_created":5,"api_response_code":"200"}
{"event":"enrich_push_events_completed","processed":50,"successful":48,"failed":2,"rate_limited":0,"elapsed_seconds":2.34,"queue_depth":245}
{"event":"github_rate_limit_warning","remaining":6,"limit":60,"percentage_used":90.0,"resets_at":"2026-02-20T15:30:00Z"}
```

### Viewing Logs

```bash
# Watch real-time logs
docker-compose logs -f web
docker-compose logs -f sidekiq

# Search logs
docker-compose logs sidekiq | grep "rate_limit"
docker-compose logs sidekiq | grep "error"
```

### Key Metrics to Monitor

1. **Ingestion Health**
   - Events fetched per interval
   - New events created
   - API response codes

2. **Enrichment Health**
   - Events successfully enriched
   - Events failed enrichment
   - Rate limit warnings
   - Elapsed time per batch
   - Queue depth (unenriched events)
   - Dead letter queue size

3. **Data Quality**
   - Orphaned events (push_events with no repository_id)
   - Failed enrichment attempts per Actor/Repository
   - Last enrichment timestamp freshness

### Queries for Monitoring

```ruby
# Queue health
PushEvent.unenriched.count
PushEvent.orphaned.count
Sidekiq::DeadSet.new.size

# Rate limiting
Rails.cache.read('github:rate_limit:remaining')
Rails.cache.read('github:rate_limit:reset')

# Enrichment status
Actor
