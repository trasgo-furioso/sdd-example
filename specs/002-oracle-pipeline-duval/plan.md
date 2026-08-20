# Implementation Plan: Oracle Pipeline — Duval County

**Branch**: `feature/001-oracle-crm-integration` | **Date**: 2026-08-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-oracle-pipeline-duval/spec.md` (R1 of parent roadmap)

## Summary

Build a continuous/incremental property data pipeline for Duval County, FL that ingests real county records, reconciles duplicates, publishes full-snapshot artifacts with delta metadata to Elephant IPFS, sends webhook events to consumers, and provides a UI for pipeline monitoring and property intelligence queries — all deployed to a hosted runtime with zero Oracle infrastructure cost.

## Technical Context

**Language/Version**: TypeScript (Node 22.18+); Python only if PySpark/Glue needed

**Primary Dependencies**:
- Elephant CLI (`elephant-cli`) for prepare, transform, validate
- Elephant MCP (`@elephant-xyz/mcp`) for MCP query layer
- Restate 1.7 for durable workflow orchestration
- DuckDB (in-process) for analytical queries over published Parquet
- `@aws-sdk/client-s3` for Filebase IPFS uploads
- `ipfs-only-hash` for local CID pre-computation
- Vercel AI SDK (`ai` package) for natural-language agent
- AWS CDK for infrastructure

**Storage**:
- Postgres 16 (pipeline query DB, Docker on EC2)
- DuckDB (analytical queries over Parquet, in-process)
- Filebase (S3-compatible IPFS pinning + IPNS management)
- Per-county buckets: `elephant-oracle-open-data-duval`, `elephant-oracle-query-table-duval`

**Testing**: Vitest (TypeScript), GitHub Actions CI

**Target Platform**: EC2 (t3.large, us-east-2) for pipeline backend + Amplify for frontend + Lambda for agent/MCP

**Project Type**: Web application (pipeline backend + operator UI frontend)

**Performance Goals**: Agent queries < 10 seconds; webhook delivery < 30 seconds post-publish; IPNS update detection < 5 minutes

**Constraints**: Zero Oracle-hosted database cost; deployed hosted runtime mandatory (no localhost); realistic data scale (100k+ Duval properties)

**Scale/Scope**: ~200k-400k Duval County properties; 6+ data sources; continuous pipeline with multiple runs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Elephant Protocol Alignment | PASS | Pipeline follows oracle skills pattern: onboard-county → stage skills → ingest → publish. Lexicon transform, CIDv1+SHA-256, Filebase IPFS, IPNS per county. |
| II. Golden Path Engineering | PASS | TypeScript everywhere, Vercel AI SDK for agent, CDK for infra, Vitest, Powertools observability, PagerDuty alerting. |
| III. Deployment-First | PASS | Deployment is Phase 0 prerequisite. Hosted runtime on AWS (Amplify + EC2/ECS or Restate Cloud). No localhost delivery. |
| IV. Realistic Data Scale | PASS | Targeting full Duval County parcel roll (200k-400k properties). Toy datasets rejected. |

No violations. No complexity tracking entries needed.

## Deployment Architecture

**Approach**: EC2 + Docker Compose (mirrors oracle-node pattern) + Amplify + Lambda

### Infrastructure Components

```
┌─────────────────────────────────────────────────────┐
│  EC2 (t3.large, us-east-2)                          │
│                                                     │
│  Docker Compose                                     │
│  ├── Restate 1.7        (ports 8080, 9070)          │
│  ├── Postgres 16        (port 5432, EBS volume)     │
│  └── Pipeline services  (port 9080, Node 22.18+)    │
│                                                     │
│  Nginx reverse proxy                                │
│  └── HTTPS via Caddy/certbot                        │
│      ├── /api/*    → Pipeline services :9080        │
│      ├── /mcp      → MCP endpoint :9090             │
│      └── /restate  → Restate admin :9070            │
│                                                     │
│  Security group: 443 (HTTPS), 22 (SSH)              │
│  EBS volume: 100GB gp3 (pipeline data + Postgres)   │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  Amplify (CDK-deployed)                             │
│  └── React frontend (static site)                   │
│      ├── Dashboard, run history, data explorer      │
│      ├── Property query UI                          │
│      └── Agent chat interface                       │
│      API calls → EC2 HTTPS /api/*                   │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  Lambda + API Gateway (CDK-deployed)                │
│  ├── Agent function (Vercel AI SDK + DuckDB)        │
│  │   └── Queries published Parquet via httpfs        │
│  └── MCP function (stateless, reads IPNS)           │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  Filebase (external, S3-compatible)                 │
│  ├── elephant-oracle-open-data-duval    (IPFS)      │
│  ├── elephant-oracle-query-table-duval  (IPFS)      │
│  └── IPNS pointers (stable, per-county)             │
└─────────────────────────────────────────────────────┘
```

### CDK Stacks

```
infra/lib/
├── pipeline-stack.ts     # EC2 instance, security group, EBS volume,
│                         # IAM role, user-data script (docker compose up)
├── frontend-stack.ts     # Amplify app, branch auto-deploy, custom domain
└── agent-stack.ts        # Lambda functions, API Gateway, IAM for DuckDB httpfs
```

### Deployment Flow

1. **`npx cdk deploy PipelineStack`** — provisions EC2 with Docker Compose user-data. On first boot: pulls images, starts Restate + Postgres + pipeline services, configures Nginx + HTTPS.
2. **`npx cdk deploy FrontendStack`** — creates Amplify app connected to repo. Auto-builds and deploys React frontend on push.
3. **`npx cdk deploy AgentStack`** — deploys Lambda functions behind API Gateway for agent and MCP endpoints.

### Why EC2 + Docker Compose

- **Fidelity**: Identical to the oracle-node pattern from elephant-xyz/skills (Docker Compose with Restate + Postgres)
- **Speed**: One CDK stack, one instance, everything running in minutes
- **Cost**: ~$25-50/mo for t3.large — our cost, not Oracle's
- **Simplicity**: No ECS/Fargate complexity for Restate persistent state
- **Deployment-first**: Infrastructure is the FIRST task, unblocking all other work

### Persistence

- **Postgres data**: EBS volume mounted at `/data/postgres`, survives instance restarts
- **Restate state**: EBS volume mounted at `/data/restate`, durable workflow journals persist
- **Pipeline artifacts**: Local staging on EBS at `/data/pipeline`, published to Filebase IPFS

## Project Structure

### Documentation (this feature)

```text
specs/002-oracle-pipeline-duval/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── webhook-event.md
│   └── published-artifact.md
├── research/            # Pre-plan research files
│   ├── elephant-protocol.md
│   ├── slowking-assessment.md
│   └── soofi-xyz-team-kit.md
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
oracle-property-intelligence-platform-pipeline-duval-fl/
├── infra/                    # CDK infrastructure
│   ├── bin/
│   └── lib/
│       ├── pipeline-stack.ts
│       └── frontend-stack.ts
├── pipeline/                 # Backend pipeline services
│   ├── src/
│   │   ├── workflows/        # Restate durable workflows
│   │   │   ├── county-ingest.ts
│   │   │   ├── ingest-chunk.ts
│   │   │   └── publish.ts
│   │   ├── services/         # Restate services
│   │   │   ├── parcel.ts
│   │   │   ├── loader.ts
│   │   │   └── webhook.ts
│   │   ├── transforms/       # Duval-specific transform handlers
│   │   │   └── duval/
│   │   ├── sources/          # Data source adapters
│   │   │   ├── appraiser.ts
│   │   │   ├── permits.ts
│   │   │   ├── ownership.ts
│   │   │   └── geo.ts
│   │   └── lib/              # Shared utilities
│   │       ├── filebase.ts
│   │       ├── ipns.ts
│   │       ├── duckdb.ts
│   │       └── provenance.ts
│   ├── data/
│   │   └── seeds/
│   │       └── duval.csv
│   └── tests/
│       ├── unit/
│       └── integration/
├── frontend/                 # Operator UI
│   ├── src/
│   │   ├── components/
│   │   ├── pages/
│   │   │   ├── dashboard.tsx
│   │   │   ├── run-history.tsx
│   │   │   ├── data-explorer.tsx
│   │   │   └── query.tsx
│   │   └── services/
│   └── tests/
├── agent/                    # Natural-language agent
│   ├── src/
│   │   ├── agent.ts          # Vercel AI SDK agent
│   │   └── tools/            # Agent tools (DuckDB queries)
│   └── tests/
├── mcp/                      # MCP server for Duval
│   ├── src/
│   └── tests/
├── docker-compose.yml        # Local: Restate + Postgres
├── package.json
└── tsconfig.json
```

**Structure Decision**: Web application with separate backend (pipeline services), frontend (operator UI), agent, and MCP server — all TypeScript. The pipeline uses Restate for durable workflows following the oracle-node pattern. Infrastructure via CDK.

## Kit Alignment

### Builder Agent: Oracle

The soofi-xyz-team-kit **Oracle agent** (`agents/oracle.md`) is the prescribed builder for this task. It orchestrates `elephant-xyz/skills` against the `oracle-node` pipeline. Reference implementation: Lee County, FL (~512k properties). Our Duval pipeline follows the same pattern, adapted for Duval County.

**Routing confirmation**: Arceus (master router) routes property ingestion + IPFS publishing tasks to the Oracle agent.

### Skills Driven

The pipeline implementation drives these `elephant-xyz/skills` in sequence — each is a defined skill, not custom architecture:

| Step | Skill | What It Does |
|------|-------|-------------|
| 1 | `bootstrap-oracle-infra` | Docker stack (Restate + Postgres), data dirs, services |
| 2 | `county-discovery` | Catalog Duval appraiser/permit portals and sources |
| 3 | `county-seed-data` | Generate parcel roll → `data/seeds/duval.csv` |
| 4 | `county-appraisal-onboarding` | Browser flow, transform scripts, smoke test |
| 5 | `validate-county-transform` | Validate 10-20 diverse parcels, 100% field coverage |
| 6 | `county-permit-adapter` | Duval permit portal harvester |
| 7 | `county-ingest-run` (pilot) | ~25 parcels end-to-end verification |
| 8 | `county-ingest-run` (full) | Full county with backpressure feeder |
| 9 | `sunbiz-corporate-ingest` | FL statewide corporate data |
| 10 | `bbb-harvest` | Contractor reputation enrichment |
| 11 | `query-db-loading-matching` | Reconcile + verify folio counts |
| 12 | `county-open-data-publish` | Export + upload + IPNS (gated) |
| 13 | `county-query-table-publish` | Parquet export + upload + IPNS + MCP wire |
| 14 | `deploy-open-data-mcp` | Add Duval to MCP IPNS maps |

### Kit Skills Used

| Skill | Purpose |
|-------|---------|
| `use-oracle` | Primary — drives onboard-county + stage skills on oracle-node pipeline |
| `apply-engineering-guidelines` | Golden Path baseline (TypeScript, CDK, Vercel AI SDK, PagerDuty, Powertools) |
| `use-elephant-mcp` | Verify published data is queryable via MCP |
| `use-elephant-query-db` | Pattern for Neon query DB consumption with Drizzle |

### Extensions Beyond the Kit

These capabilities are required by the spec but not covered by existing skills:

| Extension | Why Needed | Implementation Approach |
|-----------|-----------|------------------------|
| Webhook signaling | CRM integration contract (R2) | Add webhook dispatch to Publish virtual object post-IPNS-update |
| Delta metadata | CRM needs per-run change detection | Leverage Loader watermark diffs; publish `delta.json` alongside index |
| Operator UI | Pipeline monitoring + demo requirement | React frontend wrapping Restate state + run history |
| Proximity queries | 6 required query types (transit, Starbucks, water) | Pre-compute derived signals at ingestion from GTFS, OSM, NHD |
| Natural-language agent | Stakeholder requirement for RAG-backed Q&A | Vercel AI SDK + DuckDB tool calling over published Parquet |

### Supporting Agents

| Agent | Role |
|-------|------|
| **Arceus** | Validates Oracle is the correct agent; confirms skill routing |
| **Donphan** | Explores/verifies published MCP data post-publish |
| **Metagross** | Reference for monorepo scaffolding pattern (Turborepo, Amplify, CDK) |

## Complexity Tracking

No constitution violations to justify.
