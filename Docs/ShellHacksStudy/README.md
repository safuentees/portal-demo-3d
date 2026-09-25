# ShellHacks winner case study

Version 1.1.0. Research cutoff: 25 September 2026.

## Deliverables

- `ShellHacks_Winners_Case_Study.pdf`: 25-page report with charts, recommendations, feature matrices and all 36 project records.
- `ShellHacks_Winners_Case_Study.docx`: editable source report.
- `ShellHacks_Winners_Dataset.xlsx`: editable four-sheet workbook with sources, evidence, coding definitions and recalculating summaries.
- `dataset.json`: canonical normalized project data used for analysis.
- `ShellHacks_2026_Project_Ideas.pdf`: 17-page companion report with ten evidence-linked concepts, confirmed 2026 constraints, a comparison matrix, demonstration scenarios and proposed validation plans.
- `ShellHacks_2026_Project_Ideas.docx`: editable companion report using the same existing template.
- `project_ideas_2026.json`: structured concept records with precedent IDs, implementation scope, dependency checks and conditional challenge fit.

The original study and winner dataset remain version 1.0.0; version 1.1.0 adds the project-ideas companion. Concept order, effort estimates and team sizes are planning judgments, not statistical rankings. Validation counts are proposed acceptance tests, not collected results. Current public sources confirm the event format but do not establish a 2026 rubric, submission checklist or sponsor challenge eligibility.

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
- Ideas companion: all 17 rendered pages visually inspected; 25 PDF links and all 21 referenced project records checked. Independent evidence review found no award or capability mismatches. The finite 1,260-case proposed algorithm test domain was counted independently. Template geometry, theme, font table, numbering, web settings and original images were preserved.

All sources are public. Participant names, contact details and private account data were excluded.
