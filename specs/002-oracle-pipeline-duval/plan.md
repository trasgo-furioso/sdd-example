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
- Postgres 16 (pipeline query DB, local Docker or hosted)
- DuckDB (analytical queries over Parquet, in-process)
- Filebase (S3-compatible IPFS pinning + IPNS management)
- Per-county buckets: `elephant-oracle-open-data-duval`, `elephant-oracle-query-table-duval`

**Testing**: Vitest (TypeScript), GitHub Actions CI

**Target Platform**: Hosted web application (AWS Amplify or Vercel for UI; Restate Cloud or EC2 for pipeline services)

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

## Complexity Tracking

No constitution violations to justify.
