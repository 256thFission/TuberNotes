# TuberNotes

An open-source iPad notes app with a magic lasso that brings frontier OpenAI models straight onto your page.

## Inspiration

This app was made out of spite.

GoodNotes is the best and most popular iOS Pencil notes app. It is also, frankly, an unconfigurable $28 piece of sh*t. After spending 9+ hours a day in it—screenshotting broken PDF renders and pasting them into ChatGPT—we decided to do better.

## What it does

TuberNotes is a good notes app. What makes it *gooder* is that the magic lasso lets you select part of a page and summon GPT-5.6 right there, where you are working.

We mirrored OpenCode's implementation so you can log in with OpenAI SSO and use your ChatGPT subscription's GPT-5.6 access without paying an extra dime.

Free—if you already pay for ChatGPT :D

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
