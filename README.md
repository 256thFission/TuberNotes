# TuberNotes

**A free, open-source iPad notebook that lets you point at your work and ask GPT-5.6 about it.**

TuberNotes is for students who live in GoodNotes, keep hitting its limits, and are tired of screenshotting a page just to paste it into ChatGPT. Draw, import a PDF, circle the part you are stuck on with the Magic Lasso, and get help back on the page.

## Why we made it

This app was made out of spite.

GoodNotes is the best and most popular iOS Pencil notes app. It is also, frankly, an unconfigurable $28 piece of sh*t. After spending 9+ hours a day in it—screenshotting broken PDF renders and pasting them into ChatGPT—we decided to do better.

## What it does

TuberNotes is a real notes app first:

- Create notebooks with covers and paper templates.
- Write with Apple Pencil using pen, pencil, highlighter, eraser, and lasso tools.
- Import PDFs and images; add pages and drawing layers.
- Export a finished notebook as PDF, or as an editable `.spud` archive.
- Keep your ink, imported content, Pins, and conversations attached to the right page.

Then there is the Magic Lasso. Circle handwriting, an equation, a diagram, a PDF passage, or a worked problem. Choose **Explain**, **Check**, or **Ask**. TuberNotes sends that visual context to the model and places the result back where it belongs as an anchored Pin—so the answer stays attached while you zoom, pan, turn pages, and come back later.

It can also search an imported textbook and link a response to the exact page that supports it.

## The OpenAI thing

We mirrored OpenCode's implementation so you can sign in with OpenAI SSO and use your ChatGPT subscription's GPT-5.6 access without paying an extra dime.

Free—if you already pay for ChatGPT :D

The current sign-in route is a hackathon implementation. Your refresh grant lives in the iOS Keychain; access tokens stay in memory; the app does not ship a reusable provider API secret. A production release will use a proper TuberNotes agent gateway.

## How it works

```text
Apple Pencil selection → Magic Lasso → visual context + optional notebook/textbook search
                       → GPT-5.6 → anchored explanation Pins on the original page
```

The important bit: the AI does not drag you into a separate chat app. The page is both the prompt and the place the answer returns to.

## Run it yourself

### Requirements

- macOS with Xcode
- An iPad running iPadOS 17 or later
- Apple Pencil recommended
- An OpenAI account for live AI features

### Build

1. Clone the repo.
2. Open `TuberNotes.xcodeproj` in Xcode.
3. Select the `TuberNotes` scheme and your iPad.
4. Build and run.

The app stores notebooks locally on the device. Live AI requires you to explicitly sign in from Settings; without it, the normal notebook and drawing features still work.

## Project map

- `TuberNotes/Notebook` — library, pages, tools, import/export, and document persistence
- `TuberNotes/SpatialCanvas` — PencilKit canvas, zooming, coordinates, and Magic Lasso selection
- `TuberNotes/Pins` — anchored AI responses and Pin conversations
- `TuberNotes/AgentHarness` — the in-product AI client and OpenAI authorization boundary
- `TuberNotes/Knowledge` — notebook and imported-textbook search
- `SPEC.md` — product and implementation contract

## How we built it

Short answer: with Codex.

Long answer: agentic development is incredible at unit-testable tasks. “Does the lasso feel right?” is not one of them. Our answer was an MCP tool for taste: it queued a review request on a physical iPad, blocked, and waited for a verdict from a human holding an Apple Pencil.

That one rule kept four autonomous agents from confidently drifting the app into garbage.

## What we learned

Merging four agents' work is genuinely hard. Worktrees multiply, and permanent design docs become more of a suggestion once GPT-5.6 and merges get involved.

The fix is not better prompting. It is solid CI: Xcode compilation checks, computer-use simulator tests, and human review when taste is the actual requirement.

## What's next

Open beta. Want on our TestFlight? Email [thephilliplin@gmail.com](mailto:thephilliplin@gmail.com).

If you have ever wanted something from a notes app, our promise is to give it to you.

## License

See [LICENSE.md](LICENSE.md).
