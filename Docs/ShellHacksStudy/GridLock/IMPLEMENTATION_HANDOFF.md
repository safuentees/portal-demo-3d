# GridLock implementation handoff

26 September 2026 · Version 1.3.1 · Planning only

Build a small utility-project comparison app for Sperry. Four capable teammates and obtainable sponsor API access are confirmed. Optimize for internship value, a strong portfolio and a defensible competition entry. Hardware and remaining build time are unspecified. No implementation has started.

## Keep the rule unresolved

The prior review omitted the separate event guide. Its conclusion that closest-point distance was optional applies only to the two ZIP documents.

| Source | Required method | Unresolved details |
| --- | --- | --- |
| Separate event guide | Closest points between actual project geometries, within 40 km. | Also says “closer than”; exact equality and source precedence unresolved. |
| ZIP guide and challenge | Midpoint of two named locations, or one located point, under 25 miles. | Brief also says “within”; exact equality and source precedence unresolved. |

**Await Sperry’s reply to the user’s existing message.** Keep two labeled rule profiles and leave the authoritative profile unset. Exactly 25 miles is 40.2336 km, so both geometry and threshold differ. Do not mix profile rankings or silently substitute one method. Treat equality cases as unresolved until clarified.

The event guide’s crossing and under 1.6/8/40 km bands describe potential coordination benefits; they do not establish shared land, crews or savings. Keep construction timing separate from milestone gaps.

## Smallest working app

One web screen with an interactive map, distance-ranked candidate list and clickable evidence panel. Load the curated ten-project JSON plus public, scope-matched GeoJSON needed for the demo. A static client and small calculation module suffice; no database is required.

- Show work section, utility, dated status, source/page, date precision and geometry confidence. Separate completed/stale examples from future-plan candidates.
- Expose both pending rule profiles. Use a geodesic method or suitable metric projection for closest-point calculations, never degrees as meters. A connector represents a measurement, not a transmission route.
- Missing work geometry means **unknown**, not zero, rejection or a center-point fallback. Rank comparable results by unrounded distance within one profile; keep unknowns in an unranked review queue.
- Test crossing lines, a long line near a station despite distant centers, both threshold boundaries and missing geometry using explicitly labeled synthetic fixtures.

**Real-data demo:** Jasper–Okatie #2 / Goshen–Georgia Pacific remains the evidence-review pair. Its 10.25-mile result is a center-point proxy; closest-point distance is unknown. Milestones remain 1 December 2026 and year-only 2028; construction overlap is unknown. First obtain public geometry for both actual work sections, or select another documented future-project pair from two utilities. Never invent a straight route between endpoints. If geometry remains unavailable, demonstrate the algorithm with synthetic examples and disclose that a real closest-point match is unvalidated; do not claim full challenge satisfaction.

## Four responsibilities

| Owner | Responsibility | Deliverable |
| --- | --- | --- |
| 1 — Data and domain | Validate public work geometry, project identity, dated sources and schedules; record Sperry’s answer. | Versioned JSON/GeoJSON, source register and geometry sufficiency decision. |
| 2 — Spatial logic | Implement both rule profiles, units, unknown handling, ranking and geometry tests. | Tested calculation module with documented assumptions. |
| 3 — Product interface | Connect map, list, evidence panel and rule comparison; use accessible status/confidence labels. | Complete planner workflow explaining each match. |
| 4 — Integration and delivery | Integrate early, independently verify results, deploy/package, prepare demo and submission. | Reproducible app, acceptance checks, architecture notes and portfolio README. |

Owners 1/2 resolve geometry feasibility first; 3/4 can build against labeled fixtures. Finish one complete flow before adding data or extraction. Preserve a two-hour submission buffer; fit work and rest to the actual remaining window.

## Internship and portfolio value

Prioritize source tracing, useful validation failures, tested geometry, understandable commits and clear individual ownership. These align with the supplied Sperry internship listing’s data-quality and document-processing emphasis; they do not predict hiring or prizes. Each teammate should explain their decisions and verification in the demo.

Sperry is the primary target. The MVP needs no sponsor API. DigitalOcean hosting is a natural optional deployment; Gemini-assisted extraction with page citations and human review is a stretch only after the core works. Access is obtainable, but secondary-category eligibility remains unverified. Defer live scraping, autonomous extraction, extra databases, accounts and unsupported cost estimates.

Source wording, locators and checksums are in `rule_reconciliation.json`. This handoff supersedes the version 1.3.0 PDF/DOCX rule interpretation and team/access assumptions. Original cells, utility evidence and historical data remain unchanged. Apply current event reuse, AI-disclosure and submission rules when implementation is authorized.
