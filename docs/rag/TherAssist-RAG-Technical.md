# TherAssist RAG: How the Corpus Shapes Every Suggestion
## Technical reference

*As of 2026-09-23 · Muhammad (Mohsin) Sardar · branch `demo-readiness-2026-09-18`, Cloud Run revision `ther-assist-sidecar-00013-97d`. File paths are relative to `gcaimh-ther-assist-DEV/`.*

## 1. Overview: where retrieval happens

Every piece of guidance TherAssist shows is produced after the model has read passages retrieved from the therapy corpus; there is no path that skips retrieval. Retrieval runs in three places, using two mechanisms.

| Path | When it runs | Model | Retrieval mechanism | Corpora consulted | Typical latency |
| --- | --- | --- | --- | --- | --- |
| Real-time guidance | Every ~8 new transcript words (or 20 s after the first words) | gemini-2.5-flash, thinking off | Server-side search of Vertex AI Search (Discovery Engine) datastores; passages injected into the prompt as text | ebt-corpus, safety-crisis + the session's modality corpora | 1.5–2.5 s |
| Comprehensive analysis | Same trigger, but only one in flight at a time | gemini-2.5-pro, thinking budget 8,192 (16,384 if safety words found) | Vertex AI Search attached to Gemini as grounding tools; Gemini queries and cites | Same + transcript-patterns | 30–50 s |
| Session summary | When the therapist ends the session | gemini-2.5-pro, thinking budget 24,576 | Grounding tools, as above | Same as real-time | 40–110 s |

The two mechanisms differ in who runs the search. In the real-time path the backend (`backend/therapy-analysis-function/main.py`, `prefetch_rag_context`) searches the datastores itself, formats the hits as a `CLINICAL EVIDENCE` block, and puts that block at the top of the prompt. In the comprehensive and summary paths the datastores are attached to the Gemini call as tools (`get_rag_tools_for_session`), so Gemini decides what to look up and returns grounding chunks that become citations.

```
Speech → Speech-to-Text v2 → Transcript
   ├─ every ~8 words → Real-time: prefetch search → gemini-2.5-flash → Alert card
   ├─ every ~8 words → Comprehensive: grounding tools → gemini-2.5-pro → metrics, pathway
   └─ session end   → Summary: grounding tools → gemini-2.5-pro → summary + citations
```

## 2. The corpora

Nine Vertex AI Search datastores live in project `brk-prj-salvador-dura-bern-sbx` (location `us`); seven are wired into the app, and two of those are consulted on every call regardless of modality. Counts are live as of 2026-09-23.

| Datastore | Display name | Documents | Source bucket | Used by |
| --- | --- | --- | --- | --- |
| `ebt-corpus` | EBT Therapy Manuals Corpus | 94 | `…-ebt-corpus` (103 MB) | Every call (core protocols) |
| `safety-crisis` | Safety & Crisis Clinical Protocols | 9 | `…-safety-crisis` (7.5 MB) | Every call |
| `cbt-corpus` | CBT Clinical Research Papers | 196 | `…-cbt-material` (116 MB) | CBT sessions |
| `ba-corpus` | BA Corpus | 76 | `…-ba-corpus` (34 MB) | CBT sessions (behavioral activation) |
| `dbt-corpus` | DBT Corpus | 6 | `…-dbt-corpus` (7 MB) | DBT sessions |
| `ipt-corpus` | IPT Corpus | 75 | `…-ipt-corpus` (38 MB) | IPT sessions |
| `transcript-patterns` | Clinical Therapy Transcripts | 3,000 | `…-transcript-patterns` (67 MB) | Comprehensive analysis only |
| `mi-corpus` | Motivational Interviewing Clinical Corpus | 1 | `…-mi-corpus` | Not wired in |
| `trauma-corpus` | Trauma-Informed Care Clinical Corpus | 5 | `…-trauma-corpus` (5.8 MB) | Not wired in |

Routing is a fixed map in `main.py` (`modality_map`, line 580, and `MODALITY_RAG_MAP` for the tool path): CBT → `cbt-corpus` + `ba-corpus`; DBT → `dbt-corpus`; IPT → `ipt-corpus`; an unknown modality falls back to CBT. The safety datastore contains the 988 Lifeline risk-assessment standards and crisis protocols; `transcript-patterns` holds de-identified session excerpts that the comprehensive analysis uses to recognise process patterns such as ruptures and avoidance. Documents are parsed PDFs and text, indexed for search (`SOLUTION_TYPE_SEARCH`, standard edition, so snippets only, no extractive answers).

## 3. Triggers: what starts a lookup and what is searched

A lookup is started by the transcript, not by a keyword: every time 8 or more new final-transcript words have accumulated, the frontend (`frontend/components/NewTherSession.tsx`, `WORDS_PER_ANALYSIS = 8`) sends the last 5 minutes of transcript to the backend, which retrieves before it reasons. If the word threshold has not been met 20 s after the first words, a time-based fallback fires once.

1. **What is sent.** The final (non-interim) transcript lines from the last 5 minutes, with speaker labels, plus the session context (modality, duration, the most recent alert for de-duplication) and a shared job id so the real-time and comprehensive results can be paired.
2. **How the search query is built.** The backend joins the transcript text and uses its **last ~200 words** as the search query (`prefetch_rag_context`, line 586). There is no keyword extraction: the patient's and therapist's own recent words are the query, so a turn about "filling out the activity log" pulls behavioral-activation passages and a turn about nightmares pulls trauma and sleep material.
3. **Which shelves.** `ebt-corpus` and `safety-crisis` always, plus the modality's corpora (CBT: `cbt-corpus`, `ba-corpus`). The four datastores are searched in parallel threads with a 10 s cap each, and results are cached for 25 s keyed on the modality and a hash of the last 500 characters, so a burst of triggers does not re-query identical text.
4. **Safety keyword scanner (deterministic, runs before the model).** `detect_safety_keywords` matches the transcript against five hard-coded lists in `constants.py`: suicidal ideation (19 terms, e.g. "suicide", "kill myself", "end my life"), self-harm (14, e.g. "cutting myself"), violence/homicide (22, e.g. "kill him"), abuse disclosure (22, e.g. "hitting me"), substance crisis (17, e.g. "overdose", "relapsed"). A match forces a safety alert whatever the model says, injects a `SAFETY KEYWORDS DETECTED` block naming the matched terms into the prompt, and raises the comprehensive model's thinking budget from 8,192 to 16,384 tokens.
5. **Trigger phrases.** Four demo phrases ("something else came up", "scared but I want to do it", "very brave", "I might fall apart") switch the real-time prompt from its strict variant to a non-strict one that allows a process-level suggestion; they do not change what is retrieved.

What does not trigger retrieval: interim (partial) transcript lines, clinician notes, and anything typed into the UI. Retrieval is driven only by spoken words that Speech-to-Text has finalised.

## 4. The real-time path, step by step

A real-time alert takes 1.3–2.5 s end to end, of which 0.3–1.2 s is retrieval; the model never sees the transcript without the retrieved passages in front of it.

```
Frontend ──analyze_segment (last 5 min, is_realtime=true)──▶ therapy-analysis
therapy-analysis ── safety keyword scan
therapy-analysis ──search ×4 datastores (last ~200 words)──▶ Vertex AI Search
Vertex AI Search ──3–9 snippets + source titles──▶ therapy-analysis
therapy-analysis ──prompt = safety block + CLINICAL EVIDENCE + transcript──▶ gemini-2.5-flash
gemini-2.5-flash ──alert JSON (streamed)──▶ therapy-analysis ──alert + diagnostics──▶ Frontend
```

1. **Retrieve.** `prefetch_rag_context` searches each datastore with `SearchRequest(page_size=3, snippet_spec=return_snippet)`, keeps the snippet text and the document title as `[Source: <title>]`, caps at 6 passages per store, and joins them into one `CLINICAL EVIDENCE` block. Observed in the Jane Doe run: 3–9 passages per call, 292–1,232 ms.
2. **Assemble the prompt.** Order is fixed: an optional `SAFETY KEYWORDS DETECTED` block, then the `CLINICAL EVIDENCE (from evidence-based therapy corpus — use these to ground your guidance)` block, then `REALTIME_ANALYSIS_PROMPT` with the transcript, session phase and the previous alert (for de-duplication).
3. **Generate.** `gemini-2.5-flash`, `temperature 0.0`, `max_output_tokens 1024`, `thinking_budget 0` (set explicitly on 2026-09-18; before that dynamic thinking consumed up to 979 of the 1,024 tokens and alerts arrived title-only). No tools are attached on this path, which is what keeps it under 3 s.
4. **Parse.** The streamed text is parsed as JSON (`{alert: {timing, category, title, message, evidence[], recommendation[]}}`) with a repair pass for truncated output; `_diagnostics` records latency, tokens, `rag_tools` consulted and `grounding.chunks_retrieved` (0 on this path, because passages were injected as text rather than returned as grounding metadata).
5. **Display.** The frontend de-duplicates against recent alerts (Jaccard similarity on title and message, 3 s hard block, per-category throttles) and shows the card.

Measured on 2026-09-23, local stack and Cloud Run: median 2.0 s, max 3.5 s per alert; 23 of 23 real-time calls retrieved passages; 0 truncations.

## 5. The comprehensive and summary paths

These two paths let Gemini search the corpus itself: the datastores are attached to the call as Vertex AI Search grounding tools, the model issues its own queries while reasoning, and every passage it relies on comes back as a grounding chunk that becomes a citation.

| Aspect | Comprehensive analysis | Session summary |
| --- | --- | --- |
| Trigger | Same word trigger as real-time; skipped while one is in flight | Therapist ends the session |
| Model | `gemini-2.5-pro` | `gemini-2.5-pro` |
| Thinking budget | 8,192 tokens; 16,384 when the safety scanner fired | 24,576 tokens |
| Max output | 2,560 tokens | 4,096 tokens |
| Tools | `ebt-corpus`, `safety-crisis`, modality corpora, `transcript-patterns` | `ebt-corpus`, `safety-crisis`, modality corpora |
| Output | session metrics (engagement, alliance, emotional state, arousal), pathway indicators, modality suggestion, diarized transcript | key moments with timestamps, techniques used, risk assessment, homework, follow-ups, citations |
| Grounding seen today | 60–73 chunks per call | 9 citations on the Jane Doe summary |
| Latency seen today | 34–50 s | 40–110 s |

The tools are built once at start-up (`MANUAL_RAG_TOOL`, `SAFETY_RAG_TOOL`, `CBT_RAG_TOOL`, `BA_RAG_TOOL`, `DBT_RAG_TOOL`, `IPT_RAG_TOOL`, `TRANSCRIPT_RAG_TOOL`, each a `types.Tool(retrieval=VertexAISearch(datastore=…))`) and selected per session by `get_rag_tools_for_session`. Grounding chunks carry the source document and the retrieved text; the backend copies them into `citations[]` on the summary (title + source excerpt), which is why a summary response is ~143 KB, of which ~133 KB is citation text. The comprehensive path also uses a cached system prompt (context caching) to cut input cost; the cache is keyed to the pro model and refreshed on expiry.

## 6. Worked example from the Jane Doe session (2026-09-23, local run)

One real-time cycle, taken from `error-log-analysis.txt`, shows the whole chain from spoken words to a card in about 2.6 s.

1. **Spoken.** Speech-to-Text finalised this stretch of the synthetic session: "…let's start with the homework. Can you tell me a bit about how it went filling out that activity log? … those couple of hours on Saturday. Was that when you were planning to try baking those cookies for your sister? Yeah, it was, I actually did it, she came over…"
2. **Triggered.** The frontend had accumulated more than 8 new words, so it sent the last 5 minutes of transcript (`realtime: True`, CBT, job id shared with the comprehensive call).
3. **Scanned.** `detect_safety_keywords` found none of the 94 safety terms; no safety block was injected, prompt variant `strict`.
4. **Retrieved.** `[RAG PREFETCH] Querying 4 datastores for CBT: ['ebt-corpus', 'safety-crisis', 'cbt-corpus', 'ba-corpus']` with the last ~200 words as the query; `Completed in 548 ms — 9 passages retrieved`. The passages came back with source titles from the BA and CBT research corpora (activity scheduling, reinforcing completed activities, the discounting-positives distortion).
5. **Generated.** `gemini-2.5-flash` read the `CLINICAL EVIDENCE` block plus the transcript: `latency 2,048 ms`, 2,413 prompt tokens, 275 output tokens, finish `STOP`.
6. **Shown.** The card that appeared in the session was **"Behavioral Activation Opportunity" (technique)**, recommending that the therapist reinforce the completed activity and connect it to Jane's sense of competence, alongside earlier cards such as "Addressing Sleep Disturbances and Nightmares" and "Tracking Mood Progress". The comprehensive call for the same job id ran with the grounding tools and reported 60–62 grounding chunks.

The same session, played on the deployed Cloud Run service (`ther-assist-sidecar`), produced identical log signatures: 4 datastores per call, 3–8 passages, 73 grounding chunks on the comprehensive path.

## 7. Verifying that RAG is active, and what can go wrong

RAG is verified from the analysis log, never from the screen: a session can look normal while retrieval silently returns nothing, which is exactly what happened before 2026-09-18.

| Log line (`error-log-analysis.txt` locally, Cloud Run logs for `ther-assist-sidecar` online) | Healthy | Broken |
| --- | --- | --- |
| `[RAG PREFETCH] Querying 4 datastores for CBT: [...]` | one per real-time call | missing = retrieval not attempted |
| `[RAG PREFETCH] Completed in <ms> — N passages retrieved` | N ≥ 3 | N = 0 on every call |
| `[RAG PREFETCH] Failed to query <datastore>: ...` | absent | present (2026-09-18: `400 Cannot use enterprise edition features`) |
| `[RAG] Session type 'CBT' → tools: ebt-corpus + safety-crisis + ...` | one per comprehensive call | missing |
| `Found N grounding chunks` | N ≥ 20 on comprehensive calls | 0 |
| `Added N citations to session summary response` | N ≥ 1 | 0 |

Failure modes seen so far:

- **Enterprise-only request on a standard datastore (fixed 2026-09-18).** `_query_datastore` asked for extractive answers; Discovery Engine rejected every call with 400, the `except` swallowed it as a warning, and real-time guidance ran ungrounded for months while looking fine. Snippets-only requests fixed it; the passage count went from 0 to 7–10 per call.
- **Thinking eating the output budget (fixed 2026-09-18).** Not a retrieval bug, but it hid one: truncated alerts drew attention away from the empty evidence block.
- **Duplicate real-time requests (fixed 2026-09-18).** Every trigger fired twice from a React state updater; 80 requests per test session became 41.
- **Storage service rejecting the placeholder token online (fixed 2026-09-23).** The deployed frontend runs without Firebase and sends a placeholder token; the storage service rejected it, so the Example Audio buttons failed with 401 online. Inside Cloud Run the service now accepts requests that arrived through IAP (IAP forwards `X-Goog-IAP-JWT-Assertion`, not the email header).
- **Early "ended" from the browser's audio element (guarded 2026-09-23).** Chrome fired `ended` 8:40 into an intact 32-minute MP3, which stopped the session; an `ended` more than 2 s before the known duration is now logged and playback resumes.
- **`gcloud run services replace` switching IAP off (fixed 2026-09-23).** The service YAML lacked the IAP annotation; it is now pinned in the spec.
- **Cache masking.** Results are cached for 25 s per modality; a stale cache can show `Cache hit` lines with no new query, which is normal within a burst.
- **Service account permissions.** The runtime account needs `roles/discoveryengine.viewer` (it has it) and network egress to `us-discoveryengine.googleapis.com`; a DNS race in the gRPC client was fixed in April by sharing one client.

What is deliberately not retrieved: clinician notes, the patient record, prior sessions' transcripts, and anything typed into the UI. Configuration lives in `constants.py` (models, prompts, safety keyword lists, trigger phrases) and `main.py` (`modality_map`, `RAG_CACHE_TTL_SECONDS = 25`, per-datastore `page_size = 3`, 10 s search timeout). The hard rule for this project: both the local stack and the online deployment must always run through these datastores; a change that would bypass them is not acceptable, and every deploy is checked against the log lines above.

---

# Engineering reference

Exact values as deployed on 2026-09-23.

## How documents are parsed and chunked

Each datastore uses Vertex AI Search's layout parser (`defaultParsingConfig.layoutParsingConfig`) on the source PDFs and text, then layout-based chunking with the ancestor headings prepended to every chunk, so a passage carries its section context. Chunk size is in tokens.

| Datastore | Parser | Chunk size (tokens) | Ancestor headings | Source |
| --- | --- | --- | --- | --- |
| `ebt-corpus` | layout | 500 | yes | PDFs in `gs://…-ebt-corpus` |
| `cbt-corpus` | layout | 500 | yes | PDFs in `gs://…-cbt-material` (e.g. `CBT_103_PMC9840507.pdf`) |
| `safety-crisis` | layout | 400 | yes | PDFs incl. `988_Lifeline_Suicide_Risk_Assessment_Standards` |
| `transcript-patterns` | layout | 300 | yes | transcript excerpts (`1-p10` style ids) |
| `mi-corpus`, `trauma-corpus` | layout | 500 | yes | PMC papers |
| `ba-corpus`, `dbt-corpus`, `ipt-corpus` | layout | service default | default | PDFs |

Documents are `CONTENT_REQUIRED`, industry vertical `GENERIC`, solution `SOLUTION_TYPE_SEARCH`, standard edition. Standard edition returns **snippets** (a short highlighted extract around the matching terms, typically 1–3 sentences) and document metadata; it does not return extractive answers or segments, which is why the 2026-09-18 request for them failed with 400.

## Real-time retrieval, exact parameters

| Parameter | Value | Where |
| --- | --- | --- |
| Trigger | ≥ 8 new final words, or 20 s after first words | `frontend/components/NewTherSession.tsx` (`WORDS_PER_ANALYSIS`) |
| Transcript window sent | last 5 minutes, final lines only, speaker-labelled | same |
| Search query | last 200 words of the joined transcript text | `main.py` `prefetch_rag_context` |
| Datastores | `ebt-corpus`, `safety-crisis` + `modality_map[session_type]` (CBT → `cbt-corpus`, `ba-corpus`) | `main.py` line 580 |
| Per-datastore request | `SearchRequest(page_size=3, snippet_spec.return_snippet=True)` | `_query_datastore` |
| Passages kept per datastore | snippets + `[Source: <title>]` lines, capped at 6 | `_query_datastore` |
| Parallelism / timeout | one thread per datastore, `join(timeout=10)` | `prefetch_rag_context` |
| Cache | 25 s per modality, keyed on hash of last 500 chars | `RAG_CACHE_TTL_SECONDS` |
| Endpoint | `us-discoveryengine.googleapis.com`, location `us`, serving config `default_search` | `_search_client` |
| Model | `gemini-2.5-flash`, `temperature=0.0`, `max_output_tokens=1024`, `thinking_budget=0` | `handle_realtime_analysis_with_retry` |

The evidence block is assembled as:

```text
--- Evidence from cbt-corpus ---
[cbt-corpus:1] <snippet text>
[cbt-corpus:2] <snippet text>
[cbt-corpus:3] [Source: Cognitive-behavioral therapy for anxiety disorders: an update]
--- Evidence from ba-corpus ---
[ba-corpus:1] <snippet text>
```

and the prompt is `safety_prefix + "CLINICAL EVIDENCE (from evidence-based therapy corpus — use these to ground your guidance):" + evidence + REALTIME_ANALYSIS_PROMPT`. The template (`constants.py`, 3,887 characters) contains the transcript, the previous alert for de-duplication, the timing rules (NOW / PAUSE / INFO), the category list and the safety instructions (duty to warn, mandatory reporting, crisis resources).

## Alert JSON schema (model output, real-time)

```json
{
  "alert": {
    "timing": "now | pause | info",
    "category": "safety | technique | pathway_change | engagement | process",
    "title": "Brief descriptive title",
    "message": "Specific action or observation (1-3 sentences)",
    "evidence": ["quote(s) from the patient"],
    "recommendation": ["up to 3 actions"],
    "immediateActions": ["step to take right now"],
    "contraindications": ["what to avoid"],
    "crisis_resources": ["required for safety alerts, e.g. 988 Suicide & Crisis Lifeline"]
  }
}
```

The backend adds `timestamp`, `session_phase`, `analysis_type`, `prompt_used` (`strict` / `non-strict`), `trigger_phrase_detected`, `safety_keywords_detected`, `job_id` and `_diagnostics` (model, latency_ms, ttft_ms, token_usage incl. thinking tokens, finish_reason, rag_tools, grounding.chunks_retrieved, json_parse_success, used_fallback).

## Safety keyword scanner (`constants.py`, `SAFETY_KEYWORDS`, lines 35–78)

Case-insensitive substring match over the whole transcript segment, before any model call. A hit forces `category=safety, timing=now`, injects the matched terms into the prompt, and raises the comprehensive thinking budget to 16,384.

| Category | Terms | Examples |
| --- | --- | --- |
| suicidal_ideation | 19 | suicide, suicidal, kill myself, end my life, don't want to live, nothing to live for |
| self_harm | 14 | self-harm, cutting myself, hurt myself, burning myself, razor, blade on my skin, punching walls |
| violence_homicide | 22 | kill him/her/them, hurt them, homicidal, violent urges, weapon, gun, knife, shoot, stab, want them dead |
| abuse_disclosure | 22 | hitting me, beating me, abusing me, molested, raped, domestic violence, child abuse, elder abuse, being trafficked |
| substance_crisis | 17 | overdose, took too many pills, relapsed, using again, withdrawal |

Trigger phrases (`TRIGGER_PHRASES`, four demo phrases: "something else came up", "scared but I want to do it", "very brave", "I might fall apart") only switch the real-time prompt to its non-strict variant.

## Comprehensive and summary tools

`types.Tool(retrieval=types.Retrieval(vertex_ai_search=types.VertexAISearch(datastore="projects/…/locations/us/collections/default_collection/dataStores/<id>")))`, one per datastore, built at import time. Selection: `get_rag_tools_for_session(session_context, is_realtime)`; comprehensive adds `transcript-patterns`. Grounding chunks come back in `candidates[0].grounding_metadata.grounding_chunks[]` with `retrieved_context.title` and `.text`; the summary copies them to `citations[] = {citation_number, source}`. Budgets: comprehensive `thinking_budget=8192` (16,384 on safety hit), `max_output_tokens=2560`; summary `thinking_budget=24576`, `max_output_tokens=4096`, `temperature=0.2`.

## Deployment facts that affect retrieval

- Runtime service account `420536872556-compute@developer.gserviceaccount.com` holds `roles/discoveryengine.viewer` and `roles/aiplatform.user`.
- Online, the four containers run in one Cloud Run service (`ther-assist-sidecar`) behind nginx: `/api/analysis/` → :8081, `/api/storage/` → :8082, `/ws/` → :8083; ingress `all`, IAP on, invoker = IAP service agent only.
- IAP forwards `X-Goog-IAP-JWT-Assertion` to the containers (observed 2026-09-23); it did not forward `X-Goog-Authenticated-User-Email`. The storage service accepts requests on that basis inside Cloud Run (`K_SERVICE` set); verifying the JWT signature is planned post-conference hardening.
- Log lines to grep, local (`error-log-analysis.txt`) or Cloud Run: `[RAG PREFETCH] Querying`, `[RAG PREFETCH] Completed in <ms> — N passages retrieved`, `[RAG PREFETCH] Failed`, `[RAG] Session type`, `Found N grounding chunks`, `Added N citations to session summary response`.
