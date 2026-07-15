# TuberNotes — Product & Build Spec

> **Goal:** a prosumer, open-source iPad note-taking app with built for performance and AI support.
> You handwrite notes; you magic lasso anything on the page; the model answers *on the page* using
> real OCR, your textbooks, and web tools.

---

## 1. Prerequisites
- **Xcode** (current) and an **iPad or simulator on iOS 26.x**; an **Apple Pencil** for real testing.
- A **ChatGPT account** (Plus/Pro) — the app signs in with it via OAuth. Optionally an **OpenAI API
  key** for the fallback path.
- For the textbook indexer (Thread 3): access to a **GPU host** to run DeepSeek-OCR offline.

## 2. Thesis

**TuberNotes is GoodNotes with an agent harness.** The interaction shape is
**lasso-in → harness → toast-out**:

- **Input:** one primitive — the **Magic Lasso**. Circle anything (handwriting or printed textbook
  content), see a context menu, and pick an action.
- **Brain:** an **agent harness** that calls tools and pulls context from the notebook, indexed
  textbooks, and the web.
- **Output:** one primitive — **toasts** the model places directly on the canvas at points of
  interest. Tapping a toast streams an explanation; long-pressing opens a full chat thread.

The app signs in with the user's own GPT account (the same way the open-source coding agent
**OpenCode** does), so it is free to run and requires no API key.

## 3. Glossary

**Coined terms (this project):**
- **Magic Lasso** — the gesture for selecting a region of a page. Draws a glowing selection and
  opens an action menu (Quick Explain / Quick Answer / Quick Voice / Keyboard).
- **Toast** — a small annotation the model places on the canvas, anchored to a specific spot. Shows
  a short teaser; expands to a streamed explanation on tap.
- **Thread** — the full chat conversation behind a toast, opened by long-press.
- **Harness** — the agent layer: authentication, the tool-calling loop, and the tools themselves.

**External tech:**
- **PencilKit** — Apple's framework for Apple Pencil input, low-latency ink, and palm rejection.
- **Vision** — Apple's on-device framework; here it performs handwriting/text OCR with bounding boxes.
- **DeepSeek-OCR** — an open-source document-OCR model, strong on dense/scientific pages (math,
  tables, multi-column). It runs on a GPU, offline.


## 4. Principles & decisions

1. **Note storage is deliberately simple and fixed early.** Each note is one `Codable` JSON file;
   ink is stored as `PKDrawing` `dataRepresentation()` (base64) inside it. Engineering effort
   concentrates on the harness and the canvas, where the product's value lives.
2. **Platform:** iOS-native — SwiftUI + PencilKit + Vision, current iOS (26.x).
3. **Auth & cost:** the app authenticates with the user's own GPT account (OpenCode-style OAuth) and
   drives chat, voice, and the agentic lasso→toast loop through it. The app is free and keyless. An
   optional BYO API key is available in settings as a fallback, selected behind the `LLMBackend`
   protocol.
4. **Structured output:** the model emits toasts by calling a `place_toasts` tool whose arguments are
   the schema-validated toast array — the same tool-calling path OpenCode uses over OAuth.
5. **Toast anchoring:** each toast anchors to an OCR region ID or the lasso selection; the app
   resolves that anchor to screen coordinates through the page transform.
6. **OCR split:** on-device **Vision models** serves the live lasso/handwriting path,
   **DeepSeek-OCR** runs offline on a GPU host to pre-digest one textbook into a
   static index for fast lookup.
8. **Scope of the OAuth path:** the subscription login is scoped to personal / self-host use; the
   product presents as prosumer and single-user.

## 5. Architecture

```
  ┌──────────────────────────────────────────────────────────────┐
  │  Thread 1 · Canvas & Document (substrate)                     │
  │  PKCanvas · textbook/PDF background · PageTransform · Note store│
  └───────────────┬───────────────────────────┬──────────────────┘
                  │ transform, page context    │ note text
  ┌───────────────▼─────────┐        ┌──────────▼───────────────┐
  │ Thread 2 · Magic Lasso  │        │ Thread 4 · Toasts &       │
  │ gesture · glow · region │        │ Threads (output overlay,  │
  │ capture · intent menu   │        │ tap-stream, long-press)   │
  └───────────┬─────────────┘        └──────────▲───────────────┘
              │ LassoSelection + Intent          │ ToastPlacement + token stream
  ┌───────────▼──────────────────────────────────┴──────────────┐
  │  Thread 5 · LLM Harness & Auth (brain)                       │
  │  LLMBackend · GPT OAuth (opencode-style) · agent/tool loop    │
  └───────────┬──────────────────────────────────────────────────┘
              │ tools
  ┌───────────▼──────────────────────────────────────────────────┐
  │  Thread 3 · OCR & Knowledge (eyes)                            │
  │  Vision OCR(region)→boxes · DeepSeek offline index · search   │
  └──────────────────────────────────────────────────────────────┘
```

## 6. Shared contracts 

One small Swift module, `Contracts`, that every thread imports and codes against; the team edits it
by agreement. Ship a stub implementation of every protocol so each thread runs standalone before
integration.

```swift
// ---- Core data ----
struct Note: Codable, Identifiable {
    let id: UUID
    var title: String
    var created, modified: Date
    var pages: [NotePage]
}
struct NotePage: Codable, Identifiable {
    let id: UUID
    var drawingData: Data                 // PKDrawing.dataRepresentation()
    var background: PageBackground         // .blank | .pdf(sourceId,pageIndex) | .image(id)
    var recognizedText: [TextRegion]       // Thread 3 fills on save
}
struct TextRegion: Codable, Identifiable { // OCR output; the anchor currency
    let id: UUID
    var text: String
    var box: CGRect                        // normalized 0...1 in page space
}

// ---- Lasso handoff (Thread 2 → Thread 5) ----
struct LassoSelection {
    let id: UUID
    let pageId: UUID
    var regionRect: CGRect                 // page-normalized bounds of the lasso
    var croppedImage: CGImage              // rasterized selection (background + ink)
    var ocrText: [TextRegion]              // Thread 3 fills from the crop
}
enum Intent { case explain, answer, voice, keyboard(String) }

// ---- Toast output (Thread 5 → Thread 4) ----
struct ToastPlacement: Identifiable {
    let id: UUID
    let threadId: UUID
    var anchor: ToastAnchor
    var teaser: String                     // short label shown collapsed
}
enum ToastAnchor {
    case region(UUID)                      // a TextRegion.id
    case lasso(UUID)                       // a LassoSelection.id
    case point(CGPoint)                    // page-normalized fallback
}

// ---- The seams (protocols) ----
protocol PageContextProviding {            // Thread 1 provides
    func currentPageImage() -> CGImage
    func pageTexts() -> [UUID: [TextRegion]]
    func pageToScreen(_ p: CGPoint, page: UUID) -> CGPoint
}
protocol OCRService {                       // Thread 3 provides
    func recognize(_ image: CGImage) async -> [TextRegion]
}
protocol TextbookIndex {                    // Thread 3 provides
    func search(_ query: String, k: Int) async -> [Chunk]   // Chunk: text+source+page
}
protocol LLMBackend {                       // Thread 5 provides
    func run(_ intent: Intent,
             selection: LassoSelection,
             context: AgentContext) -> AsyncStream<AgentEvent>
}
enum AgentEvent {
    case toolCall(name: String)            // drives a "thinking…" affordance
    case toasts([ToastPlacement])          // model called place_toasts
    case token(threadId: UUID, String)     // streaming body for a toast/thread
    case done(threadId: UUID)
}
```

`AgentContext` bundles the tool implementations (`OCRService`, `TextbookIndex`, web search,
`PageContextProviding`) that Thread 5 wires as agent tools.

## 7. The 5 parallel threads

Each thread owns its own module; the only shared module is `Contracts`. Each thread reaches a
**demoable-alone** bar against stubs before integration.

| # | Thread | Owns (module) | Depends on | Demoable-alone bar |
|---|--------|---------------|------------|--------------------|
| 1 | **Canvas & Document** | `Canvas/` — app shell, `PKCanvasView` page, textbook/PDF background, `PageTransform`, `Note` store + JSON persistence + relaunch | `Contracts` | Draw ink + show a textbook page; relaunch reopens from disk unchanged |
| 2 | **Magic Lasso & Intent** | `Lasso/` — gesture, glow/haptics animation, region→bbox→rasterized crop, radial menu (Explain/Answer/Voice/Keyboard) | `Contracts`, `PageContextProviding` | Lasso a region → glow fires → menu appears → emits `LassoSelection`+`Intent` |
| 3 | **OCR & Knowledge** | `Knowledge/` — Vision `recognize(image)→[TextRegion]`; offline DeepSeek-OCR indexer script + shipped index; `search()` retrieval; web-search tool | `Contracts` | CLI/test: image→regions w/ boxes; query→ranked textbook chunks |
| 4 | **Toasts & Threads** | `Toasts/` — overlay layer, anchor toasts via transform, tap→typewriter stream, long-press→full chat thread UI | `Contracts`, `PageContextProviding` | Canned `ToastPlacement`s + fake token stream → toasts land, tap streams, long-press opens thread |
| 5 | **LLM Harness & Auth** | `Harness/` — `LLMBackend`, GPT OAuth login (opencode-style device/browser flow, Keychain token store + refresh, request transform, `store:false`), agent tool-loop, tools: `place_toasts`, `search_textbook`, `notebook_context`, `web_search`; BYO-key fallback | `Contracts` | Console harness: hardcoded selection → real OAuth call → prints `place_toasts` args + streamed body |

### Thread notes
- **T1** is the substrate every thread imports. Land `PageContextProviding` + a page↔screen
  coordinate transform (`PageTransform`) first (Hour 0–2) to unblock T2/T4.
- **T2**: the lasso captures a page region — background pixels (textbook) plus ink — and rasterizes
  it to `croppedImage`. The glow is an animated gradient mask on the lasso path with a haptic tick.
- **T3**: the DeepSeek-OCR indexer runs offline on a GPU host and emits an index (SQLite/JSON) the
  app bundles. Retrieval starts as BM25/keyword search on-device; embeddings are an upgrade. Vision
  serves the live path on-device.
- **T4**: placement resolves `ToastAnchor.region(id)` → `TextRegion.box` → `pageToScreen`. The body
  streams on tap (typewriter effect); long-press continues the same `threadId` as a chat thread.
- **T5**: `place_toasts` is the structured-output mechanism — a tool whose arguments are the toast
  array. Authentication uses an OAuth device/browser flow against the user's GPT account, stores
  tokens in the Keychain with automatic refresh, and formats tool calls in the model backend's
  expected request shape. The `LLMBackend` protocol keeps BYO-key a one-line swap.

## 8. Integration sync points

- **Sync A (end of Hour ~2):** `Contracts` frozen + stubs merged. Everyone pulls, then diverges.
- **Sync B (hero slice):** T1+T2+T3(Vision)+T4+T5 wire the one gesture:
  lasso → Vision OCR the crop → `LLMBackend.run(.explain)` → `place_toasts` → one anchored,
  streaming toast → long-press thread. **This is the demo; reach it first.**
- **Sync C:** attach real tools — `search_textbook` (pre-baked index) + `notebook_context` +
  `web_search` — so answers cite the textbook and the notebook.
- **Sync D (seasoning):** Quick Voice, jump-to-page links, Excalidraw/Mermaid rendered in a `WKWebView`.

Build order: **hero slice → tools → seasoning.** The hero slice stands alone as a complete demo.

## 9. Milestones

- **M0 (all, Hour 0–2):** `Contracts` + stubs; T1's transform + persistence skeleton live.
- **M1 (parallel):** each thread reaches its demoable-alone bar against stubs.
- **M2 = Sync B:** hero slice integrated end-to-end on OAuth.
- **M3 = Sync C:** real context/tools attached; textbook citations appear in toasts.
- **M4 = Sync D:** seasoning as time allows.

## 10. Demo script (3 min)

Open a STEM textbook page in a notebook → **lasso** a gnarly equation (glow + haptic) → tap
**Quick Explain** → a toast lands on the equation and **streams** an explanation that cites the
textbook → **long-press** it → full thread, ask a follow-up by **voice** → close on the pitch:
*"Real OCR, knowledge from your own textbooks, answers right on the page — and you just logged in
with your GPT account."*

*(Hero-subject assumption: a STEM textbook page. A different hero subject changes only Thread 3's
OCR/index tuning.)*

## 11. Verification

- **T1:** create note → discard memory → reopen from disk → ink + background survive.
- **T2:** the emitted `LassoSelection.regionRect` matches the drawn bounds; menu intents fire.
- **T3:** a known handwriting image yields expected tokens; a known query ranks the right textbook chunk top.
- **T4:** canned placements land within tolerance of their region boxes; tap streams; long-press reuses the thread.
- **T5:** OAuth login persists across relaunch (Keychain); a hardcoded selection yields a real
  `place_toasts` tool call + streamed body.
- **End-to-end:** run the §10 script on an iPad.

## 12. Other goals:

Multi-page reflow; document-library polish and thumbnails; Nice looking tool pallet,
GoodNotes migration machinery?

## 13. Items to confirm during build

- The exact OAuth request/tool wire-format for the GPT account model backend (T5).
- The GPU host for the offline DeepSeek indexer run (T3).
- Subscription rate-limit behavior under demo load — the BYO-key fallback stays one toggle away (T5).
