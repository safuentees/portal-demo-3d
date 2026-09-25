# Independent evidence and coding audit

Reviewed 2026-09-25. Scope: all 36 project records in the four edition research files (31 overall-category projects and five supplementary 2025 winners), plus the 2026 context file. This audit reviews consistency of the complete extracted dataset and rechecks primary sources for consequential or ambiguous classifications. It does not independently run the projects, reproduce judging, or establish that public pages remain identical to event-day submissions. Research JSON files were not changed.

## Recommended normalized codebook

Use `yes` for explicitly documented evidence, `unknown` for undocumented or ambiguous evidence, and `no` only for explicit exclusion. Collapse `not_evidenced` into `unknown` in charts, retaining the original code and evidence in the audit trail. Chart percentages should mean **documented prevalence**, with the full cohort as denominator. They must not be presented as estimated real-world absence/presence rates.

| Field | Positive evidence | Exclusions and limits |
| --- | --- | --- |
| Defined use case | A specific task, problem, target situation or engineering objective. | Does not require a human beneficiary; The Tilter has an engineering objective. Does not establish market demand. |
| Concrete input/output workflow | The description identifies an input/action and an observable output/result. | A concept or partial prototype may qualify as a **described** workflow; keep implementation status separate. Do not rename this field “working end-to-end product.” |
| Runtime AI/ML | A named learned model, AI inference API, or explicit statement of a currently implemented ML model. | Exclude AI used only to write code, future plans, generic automation, deterministic rules, PID, regex and untrained decision trees. Generic computer vision/sentiment analysis without method detail remains unknown. |
| External API/service | An externally operated API, remote data source, cloud/database/hosting service or named network service used by the prototype or its supporting site. | A local library, operating-system API, GPIO interface, self-hosted local blockchain, or GitHub source link alone does not qualify. ngrok and Wix hosting qualify under this broad definition, but are not “core cloud AI.” |
| Accessibility/inclusion | An explicit condition, impairment or underserved population, coupled with a barrier-reduction goal. | Generic simplicity, general affordability, entertainment or beginner-friendliness alone does not qualify. This is intended inclusion, not accessibility compliance or validated benefit. |
| Social/environmental purpose | Explicit health, learning/student support, civic, environmental, safety or community-benefit purpose. | This is a broad, interpretive **stated-purpose** code. Generic commercial efficiency or productivity alone does not qualify. Local-economic-benefit cases must be handled consistently. |
| Interface/demonstrator | Described UI, terminal interaction, visualization, VR experience or physical demonstrator. | Does not mean a polished GUI, successful live demo, complete product, or independently inspected video. Keep sock.it unknown unless additional source evidence is collected. |
| Additional hardware | An additional physical installation, circuit, sensor or headset integral to the prototype; commodity cameras and VR devices can qualify. | Ordinary phones/laptops and their standard camera/microphone/speaker I/O do not qualify. Do not call this “custom hardware.” Ping Path requires a declared rule for its built-in LiDAR; see below. |

## Specific corrections and boundary decisions

1. **Rent-A-Plug external API/service: change yes to unknown.** The project describes a private test blockchain running between the team's computer and Raspberry Pi. GPIO and Web3 APIs are local interfaces to that setup; an externally operated service is not established. Keep hardware yes and runtime AI unknown. [Primary description](https://devpost.com/software/rent-a-plug).

2. **Tango social/educational purpose: recommend yes under the broad education rule.** It explicitly teaches dance with feedback; excluding that while including algorithm education and generative historical exploration is inconsistent. If using a narrower public-benefit rule instead, document and recode all learning cases together. Keep accessibility unknown: home access alone is not a specific inclusion mechanism. [Primary description](https://devpost.com/software/tango-dikvm2).

3. **Ping Path hardware needs an explicit boundary.** Its LiDAR sensor is built into a Pro iPhone/iPad. Under a literal “extra hardware beyond a phone” rule, change yes to unknown and annotate “phone-integrated LiDAR.” Alternatively retain yes only if the published codebook explicitly includes specialized built-in sensing, and label the measure “specialized sensing or additional hardware.” Never describe this case as custom hardware. [Primary description](https://devpost.com/software/ping-path).

4. **Do not equate interfaces with graphical polish.** Social Distance Beer Pong uses a terminal and physical cups; Rent-A-Plug and The Tilter have physical demonstrators. The existing flag can support “documented interface or demonstrator,” not “all winners had polished UI.” sock.it remains undocumented. [Beer Pong](https://devpost.com/software/social-distance-beer-pong-8nkfe6), [The Tilter](https://devpost.com/software/the-tilter).

5. **Keep runtime-AI unknown for EcoSort.** Vibe coding/Base44 and the team's ML skills do not identify the runtime classifier. The team explicitly cut hardware; keep hardware no. Keep mapping/pickup/rewards claims qualified because features and future extensions overlap in the narrative. [Primary description](https://devpost.com/software/ecosort-ofyuie).

6. **Keep runtime-AI yes for DAOchow, but qualify task detail.** Its primary narrative explicitly says TensorFlow was implemented for an ML model, which meets the self-report code. The model's task and evaluation are unspecified. Placement of new fridges using USDA data is future work, not evidence of an implemented allocation model. [Primary description](https://devpost.com/software/daochow).

7. **Retain uncertain AI codes for IntelliSchedule and The Tilter.** Sentiment analysis and computer vision can be implemented without learned models. Do not promote them to AI solely because they sound intelligent. IntelliSchedule's chatbot is future work. [IntelliSchedule](https://devpost.com/software/intellischedule), [The Tilter](https://devpost.com/software/the-tilter).

8. **Preserve the current/future distinction in No Vote Left Behind, Speak Free and ESPER.** Their proposed future ML must not enter runtime-AI counts. Speak Free's reactive audience/virtual assistant is not itself proof of learned AI. [No Vote Left Behind](https://devpost.com/software/no-vote-left-behind), [Speak Free](https://devpost.com/software/speak-free), [ESPER](https://devpost.com/software/esper-fy6xeh).

9. **Keep Lumi Lens AI yes because Gemini dialogue worked, with simulation explicitly stated.** Do not turn this into a claim of reliable live facial emotion recognition or validated neurodivergent support. The project describes hardware glasses and a working overlay with simulated emotional input. [Primary description](https://devpost.com/software/magical-girl-os).

10. **Kudos and Saberfy are clear counterexamples to universal completeness.** Kudos lists fixing authentication, continuing mobile construction and reward-finance implementation as next steps. Saberfy lacked direct website/server integration. A described input/output path is not evidence that every stage was connected. [Kudos](https://devpost.com/software/kudos), [Saberfy](https://devpost.com/software/saberfy).

11. **Apply social-purpose coding consistently across commercial/community boundaries.** Pocket Park and Bizchain both claim benefits to local businesses, so keep both yes if community-economic goals qualify. Do not imply verified public benefit or nonprofit status. IntelliSchedule can qualify as student decision support under the broad rule; generic task productivity in Kudos and job-application organization in JAM remain outside that rule. Explain that this is analyst coding, not an organizer-provided classification. [Pocket Park](https://devpost.com/software/pocket-park), [Bizchain](https://devpost.com/software/we-can-change-this-at-any-time), [IntelliSchedule](https://devpost.com/software/intellischedule).

12. **Accessibility labels are supported but reflect intended users.** Speak Free explicitly targets anxiety/glossophobia; Agent Zero explicitly targets people unable to afford professional protection. These meet an inclusion definition broader than physical disability. Do not write “nine disability tools” if the count includes financial inclusion. [Speak Free](https://devpost.com/software/speak-free), [Agent Zero](https://devpost.com/software/agentzero-tnh9p3).

## Use-case and input/output review across all records

All 36 records identify a concrete use case or engineering objective. A conservative **described input/output workflow** count is 35/36: sock.it identifies sensing and infant monitoring, but its implementation narrative stops before specifying the output path. The 35 include incomplete, simulated and self-reported prototypes. This is a documentation statistic, not a completion statistic.

| Edition | Project | Use case | Described input → output | Evidence limitation |
| --- | --- | --- | --- | --- |
| 2017 | Rent-A-Plug | Timed power rental | Token payment → outlet activation | Private test network. |
| 2017 | Pocket Park | Parking reservation | Location/selection/payment → reserved space | Demand/adoption not measured. |
| 2017 | Mic Drop | Shared venue microphone | Phone microphone → host audio | Additional hosting/security work deferred. |
| 2018 | HurriHome | Home monitoring during evacuation | Home sensor readings → app/map status | Connectivity and power resilience unresolved. |
| 2018 | Speak Free | Public-speaking practice | Speech → reacting virtual audience | Therapeutic benefit unvalidated. |
| 2018 | Remote Game Sharer | Remote game control | Client input → emulated host controller | Sparse implementation details. |
| 2018 | JAM | Application tracking | Job application details → comparison dashboard | Future college-application feature excluded. |
| 2019 | Freetear | Deployment setup | App/templates/credentials → free-tier deployment | No measured time savings. |
| 2019 | No Vote Left Behind | Voter registration access | Credential + form → populated PDF/transmission | Legal/security/registration outcome not verified. |
| 2019 | sock.it | Infant monitoring | Heart/oxygen sensing → output unspecified | **Unknown complete workflow**; sparse page. |
| 2020 | Farsense | Remote environmental sensing | Weather sensors → mesh/dashboard | Damage prediction not established. |
| 2020 | Social Distance Beer Pong | Distant social gameplay | Cup sensors → terminal game state | No risk-reduction measurement. |
| 2020 | CloudPlate | Dealership check-in | Camera plate image → customer dashboard/message | No OCR/service-time benchmark. |
| 2021 | Tango | Dance learning | Reference + dancer video → feedback/chart | Coaching efficacy not evaluated. |
| 2021 | Bizchain | Crypto commerce/portfolio | Market/user inputs → trades/alerts/dashboard | Financial performance not validated. |
| 2021 | Kudos | Collaborative productivity | Tasks/completion → collaboration/rewards | **Concept/partial**: authentication and rewards incomplete. |
| 2022 | The Tilter | Control engineering | Ball image position → servo balancing | Engineering demonstration, no human beneficiary needed. |
| 2022 | Pegasus | Search/security workflows | CSV/code upload → query/scan results | Regex, not evidenced ML. |
| 2022 | Saberfy | Custom game map generation | Song link → Beat Saber map files | Website/server integration incomplete. |
| 2022 | DAOchow | Community food access | Community/DAO actions → managed funds and food access | Coarse workflow; no proof of deliveries or corruption prevention. |
| 2022 | AlgoSaurus | Sorting education | Algorithm/speed/size choice → sorting animation | Learning gains not measured. |
| 2022 | Ping Path | Accessible navigation | LiDAR/world data → spatial-audio guidance | Device support narrative inconsistent. |
| 2023 | Chess 10 | Novel chess gameplay | Player moves → altered-rule board state | Not a measured originality result. |
| 2023 | IntelliSchedule | Course choice | Course/review data → inline ratings/summary | Sentiment method unspecified. |
| 2023 | MedVoyage | Symptom guidance | Answers → decision-tree suggestion | No diagnostic validation. |
| 2024 | ESPER | Flash-exposure reduction | Video luminosity → adjusted brightness/dashboard | No seizure-prevention efficacy established. |
| 2024 | ARSL | ASL alphabet learning | Scene/hand poses → instructions/haptic feedback | Recognition improvement needed. |
| 2024 | Diffusion Earth | Exploratory learning | Image/prompt/address + movement → generated views | Not factual historical reconstruction. |
| 2025 | EcoSort | Disposal guidance | Item photo → category/tips/history | Runtime classifier unspecified. |
| 2025 | FloodGuard | Flood preparedness | Weather/infrastructure/alert inputs → risk coordination | Direct city connections and delivery extensions deferred. |
| 2025 | Lumi Lens | Assistive social interaction | **Simulated emotion** → Gemini dialogue/overlay | Live recognition deferred. |
| 2025 | Happy Head | Sporting-impact monitoring | Motion readings → alerts/log/chart | Not a concussion diagnosis. |
| 2025 | A11y Tools | Web access | Voice/text/tool selection → page assistance | Some functions incomplete; testing quota constraints. |
| 2025 | GreenLight | Driving education | Uploaded video → reconstruction/quiz | Real-time dashcam deferred. |
| 2025 | Quests and Conflicts VR | Branching entertainment | Player choices → VR narrative branch | MVP; publication deferred. |
| 2025 | Agent Zero | Invoice-risk review | Invoice/context → aggregated risk assessment | Public evaluation numbers not established. |

## Report-level safeguards

- Use the 31-project overall cohort for primary cross-year percentages. Present the five 2025 supplementary winners separately. Combining them without separation overweights recent AI/social-purpose sponsors.
- The overall cohort includes both 2018 third-place award records and both 2022 divisions. Name these exceptions rather than claiming exactly three overall projects per year.
- The three 2025 winners share a combined overall label; their individual ordering is unknown. Do not derive rank from gallery order.
- Winner-only sampling supports “observed among the sampled winners,” not “increases odds of winning” or a predictive scoring model. There is no nonwinner control, judge-score dataset or randomized design.
- State the actual universe: all nine completed editions with public evidence, 2017–2025, sampled overall winners plus selected 2025 category cases. This is not an all-winners census.
- Avoid confidence intervals suggesting a probability sample. Descriptive counts with transparent denominators are sufficient.
- Avoid unsupported outcome verbs: prevents, cures, protects, eliminates fraud, ensures fair voting, proves market fit. Prefer intended to, designed to, or team reports.
- Diffusion Earth's frame-time reduction is self-reported; no other performance or effect size should be inferred from testimonials or prototype images.
- The 2020 Wolfram recognition does not demonstrate technical integration. Do not infer sponsor awards from named technologies or matching challenge prompts.
- Devpost participant counters are not physical attendance; gallery counts are snapshots; observed badges on the first two pages are not an exhaustive winner count. Do not calculate an event win rate from incompatible counts.
- Source pages are mutable after the event. Recency comparisons may combine historical implementations with later-edited descriptions.
- Cross-year sponsor and judging changes affect opportunity. A recent AI cluster can describe the sample without establishing AI as a timeless winning requirement.

## Audit status

All four project research files parsed successfully; 36 distinct project records reviewed. Consequential classifications were checked against project text through web retrieval; public HTML was also retrieved for Speak Free and DAOchow when the web extractor could not open them. The audit recommends changes only; the report author must record chosen codebook boundaries and apply them consistently in the normalized dataset and figures.

### Normalized dataset follow-up

The subsequently reviewed `dataset.json` resolves the material boundary issues: Rent-A-Plug external-service evidence is not established, Tango is included under the broad learning/social-purpose rule, and the hardware definition explicitly includes built-in LiDAR and dedicated commodity cameras. Its two-state presentation (`yes` / `not_established`) is acceptable because original source files preserve the distinctions and the dataset explains that lack of established evidence is not absence.

Recalculated primary-cohort totals agree: 31 defined tasks; 30 described workflows; 30 interfaces/demonstrators; 23 external API/services; 20 social/educational/community purposes; 12 specialized hardware/sensing cases; nine runtime-AI cases; seven inclusion cases. Denominator is 31 overall-category projects. Supplementary counts remain separate.

One minor data-cleanup issue remains: `rank` is null for the seven 2017–2018 records despite explicit award strings. If rank is exposed to readers, populate 1/2/3 from those labels (both JAM and Remote Game Sharer = 3). Keep 2025 combined-label ranks null. This does not alter any feature count.

The remaining material caveats are inferential rather than coding errors: no nonwinner comparison, no event-day source snapshot, mixed historical criteria and sponsor opportunities, unvalidated social/medical/financial benefit, and several incomplete or simulated implementations. The report's proposed build criteria should be presented as evidence-informed recommendations, not necessary or sufficient conditions for winning. The 2026 context correctly distinguishes a current event from the historical cohort and labels the 2025 rubric as historical only.
