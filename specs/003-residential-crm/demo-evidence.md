# Demo Evidence: Residential Property Acquisition CRM

**Date**: 2026-08-24
**Runtime**: https://feature-003-residential-jax-crm.d2nys96ft16522.amplifyapp.com/
**API**: https://42trwtmqqe.execute-api.us-east-2.amazonaws.com
**Method**: Playwright MCP browser automation against deployed runtime

## V1: Map-Based Property Discovery (PASS)

**Screenshot**: `evidence/crm-map-only.png`

- Interactive map centered on Jacksonville/Duval County with clustered property markers
- 2,000 real COJ parcels loaded via DuckDB-WASM from IPFS Parquet
- Cluster counts visible (2-35 per cluster)
- Draw Polygon / Draw Radius tools for geographic filtering
- Map/Split/List view toggle
- Clicking property opens detail panel with:
  - Address, city, parcel ID
  - Valuation (assessed + market)
  - Ownership (name, tenure years, regional owner flag)
  - Property (year built, roof age)
  - Location (coordinates, water proximity, transit distance)
  - Provenance (6 contributing sources, pipeline run ID, collection timestamps per source)
  - Create Opportunity button

## V2: Criteria Search and Saved Searches (PASS)

**Screenshot**: `evidence/crm-filtered-results.png`

- Filter fields: Ownership Tenure, Roof Age, Assessed Value Min/Max, Water Proximity, Regional Owner, Zip Codes
- Applied filters (tenure >= 10, roof >= 15, zip 32210): 9 results from 2,000
- Match score column showing 100% for full matches
- "Filtered: 9 results" badge
- Save Search button persists criteria as named search
- "Arlington Distressed" saved search recalls to 779 results
- Clear button restores full 2,000 dataset

## V3: Webhook and Proactive Notifications (PASS)

**Screenshot**: `evidence/crm-notifications.png`

- POST to /webhook/pipeline with HMAC-SHA256 signature returns {"status":"accepted"}
- Summary notification generated: "3 new, 1 updated matches for 'Arlington Distressed'"
- Notification bell badge shows unread count (1)
- Notification page: total/unread count, criteria set filter, date filters
- Each notification shows: summary, run reference, match count, timestamp, New badge
- Mark All Read button

## V4: CRM Acquisition Workflow (PASS)

**Screenshot**: `evidence/crm-opp-contacted.png`

- Create Opportunity from property detail (duplicate guard present)
- Stage tracker: visual pipeline with numbered circles (1-5 + X)
- Stages: Identified -> Contacted -> Negotiating -> Under Contract -> Closed -> Dead
- Stage change prompts for note with confirmation dialog
- Stage history with timestamped entries and notes ("Spoke with owner, interested in selling")
- Opportunity detail: email, phone, owner interest, asking price, offer amount, notes, next steps
- Task assignment section
- Opportunities page: filterable by stage, zip code, min score, date range
- Tab counts update on stage changes (Identified 4, Contacted 1)

## V5: Mocked Outreach Campaigns (PASS)

- Outreach panel on opportunity detail with 3 channel buttons: Email, SMS, Direct Mail
- Email form: recipient + subject fields
- Sent outreach appears in history table: channel, recipient, status (sent), timestamp
- Simulated lifecycle tracking (Sent -> Delivered -> Replied/Bounced)

## V6: Natural-Language Agent Queries (PASS)

**Screenshot**: `evidence/crm-agent-fixed.png`

- "Property Agent" side panel with chat input
- Query: "Show distressed properties in Arlington with roofs older than 15 years that have not sold in 10+ years"
- 20 property results returned across Arlington ZIP codes (32211, 32225, 32246)
- Each result: address, parcel ID, assessed value, roof age, tenure, 6-source provenance
- Results are clickable deep links to property detail (/?parcel=...)
- Vercel AI SDK + Amazon Bedrock + DuckDB Node on Lambda
- Neighborhood-to-ZIP mapping for Jacksonville areas

## V7: Export (PASS)

- Export CSV button on Opportunities page
- Downloads file: opportunities-export-2026-08-24.csv
- Columns: id, parcel_id, address, stage, owner_name, contact fields, financial fields, notes, timestamps
- All 5 opportunities exported with complete attributes
- Also available on property list (Export CSV)

## V8: End-to-End Flow (PASS)

Completed in sequence without leaving the CRM:
1. Defined criteria (V2) -> 2. Sent webhook (V3) -> 3. Notification appeared -> 4. Created opportunity (V4) -> 5. Sent outreach (V5) -> 6. Advanced stage

## Infrastructure Evidence

- **Frontend**: AWS Amplify (auto-deploy from GitHub push)
- **Backend**: API Gateway v2 + Lambda (CDK-managed)
- **Database**: Neon Postgres (Drizzle ORM) for CRM state
- **Property data**: DuckDB-WASM (client) + DuckDB Node (Lambda) over IPFS Parquet
- **IPNS contract**: Resolves to index.json -> query_table_cid -> Parquet
- **Observability**: Powertools Logger/Tracer/Metrics, PagerDuty alerting, CloudWatch metrics
- **No Oracle hosted-DB cost**: All property data from IPFS; CRM state in CRM-owned Neon
