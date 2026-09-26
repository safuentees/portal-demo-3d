# ShellHacks winner case study

Version 1.2.0. Sponsor review updated 26 September 2026; historical cohort cutoff remains 25 September 2026.

## Deliverables

- `ShellHacks_Winners_Case_Study.pdf`: 25-page report with charts, recommendations, feature matrices and all 36 project records.
- `ShellHacks_Winners_Case_Study.docx`: editable source report.
- `ShellHacks_Winners_Dataset.xlsx`: editable four-sheet workbook with sources, evidence, coding definitions and recalculating summaries.
- `dataset.json`: canonical normalized project data used for analysis.
- `ShellHacks_2026_Project_Ideas.pdf`: 27-page companion report with eight confirmed challenge briefs, an 80-cell adaptation matrix, fourteen scored concepts, top-three recommendations, validation plans and a four-person build schedule.
- `ShellHacks_2026_Project_Ideas.docx`: editable companion report using the same existing template.
- `project_ideas_2026.json`: unchanged original ten concept records with historical precedent IDs.
- `sponsor_challenges_2026.json`: eight confirmed challenge records separating requirements, suggestions, prizes, eligibility and gaps.
- `challenge_briefs_2026.txt`: public challenge text supplied by the user; trailing whitespace normalized, with original and normalized checksums recorded.
- `research_sponsor_adaptations_2026.json`: all 80 idea–challenge judgments, explanations, sources and adaptation deep dives.
- `sponsor_evaluation_2026.json`: four fresh concepts, all fourteen criterion ratings, weights, ranking, conditions and sensitivity.
- `research_rules_2026.json`: current official-source checks, access limits and the exact material needed to resolve local rules.

The original study and winner dataset remain version 1.0.0. Version 1.1.0 introduced the ten concepts; version 1.2.0 evaluates them alongside four fresh concepts against the eight challenges whose 2026 applicability the user confirmed. Additional organizer or sponsor challenges may exist. The user’s reply “4” is treated as four teammates; skills, hardware and remaining time are unspecified.

The preferred project is ReplayBench with Tiger Data (91/100), followed by Handoff Lab with ElevenLabs (86) and LineCheck with Gemini API (83), conditional on participant/event eligibility, skills, service access and time. The scores are explicit planning judgments: challenge fit 20%, useful integration 20%, feasibility 20%, differentiation 15%, demonstrability 15% and dependency safety 10%. They are not official judging scores, learned findings or winning probabilities. Two candidates are held for additional hardware or trust/skill gates; equal totals share rank. All validation targets are proposed tests, not measured results.

Current general MLH policies inform the review, but local submission requirements, reuse/disclosure details and multi-category entry/award limits are unresolved. Secondary sponsor combinations describe technical compatibility only. No prebuilt application code is recommended and no project implementation was started. The 36-hour plan is a full-window baseline; it is not a statement of remaining time.

## Coverage and interpretation

All nine completed editions, 2017–2025. The primary cohort is 31 overall podium projects, including both 2018 third-place recipients and separate 2022 virtual and in-person podiums. Five purposively chosen 2025 category winners are supplementary and excluded from primary percentages. Individual 2025 podium ranks are not established by their combined award label. The 2026 edition was incomplete at the cutoff.

The six principal documented-trait counts in the primary cohort are interface/demonstrator 30, external service 23, social/educational goal 20, specialized sensing/device 12, runtime AI/ML 9 and inclusion 7. All 31 have a specific task; 30 describe a sufficiently clear input-to-output workflow.

`not_established` is not a confirmed absence. Features are participant descriptions, not independently tested capability or impact. This winners-only dataset cannot establish causation or winning probabilities. The report separates observations, interpretation and suggested actions.

Raw `research_*.json` files preserve collection notes. They are provisional inputs; final harmonized coding is in `dataset.json`. In particular, Tango counts as educational benefit and Rent-A-Plug's local/private software interfaces do not qualify as external hosted services. `audit_notes.md` records the independent coding review.

## Template provenance

Adapted from Smartsheet's existing Case Study Report Template for Microsoft Word:
https://www.smartsheet.com/content/case-study-templates

Original asset:
https://www.smartsheet.com/sites/default/files/2024-03/IC-Case-Study-Report-Template-for-Microsoft-Word_WORD.docx

Original SHA256: ad8fd0ff744a7690e4c40e55120f7f3706069df86e33a6a9bcdf7e469fabd113

The report retains the landscape geometry and source cover illustration and adapts the report structure, type, tables and navigation. Smartsheet is not the author or sponsor of the analysis. The downloaded reference and QA renders are retained in the task's temporary working directory, not shipped as deliverables.

## Verification

- Independent content review: all 36 catalogue entries and links present; matrix codes match the canonical dataset; numerical totals and period comparisons match.
- DOCX rendered through the bundled renderer; every page visually inspected at full resolution. Final PDF has 25 pages and 60 hyperlink annotations, with no blank pages or source-template placeholders.
- Preserved source template theme, font table, numbering, web settings and original image parts verified byte-for-byte.
- Workbook: four sheets visually inspected, cohort formulas checked, recalculation tested, no formula errors, native chart, filters and frozen panes verified in exported XLSX.
- JSON parse and Git whitespace checks passed. No app code changed; the unrelated Metal/GPU build was not rerun.
- Original ideas companion (version 1.1.0): all 17 rendered pages and 21 referenced project records were checked. The proposed finite algorithm test domain was independently counted.
- Updated sponsor companion (version 1.2.0): all eight challenge records, 80 fit cells, fourteen weighted totals, shared ranks and historical anchors independently reviewed. All 27 final pages visually inspected; 40 PDF hyperlink targets and all 12 historical IDs used in the updated report checked. Scores independently recomputed, shared ranks verified, source-ID namespaces separated and source text checksum verified. Retained theme, numbering, font table, web settings, images and section geometry match the reference. Historical report, workbook, dataset and original ten concept records are byte-for-byte unchanged.

All sources are public. Participant names, contact details and private account data were excluded.
