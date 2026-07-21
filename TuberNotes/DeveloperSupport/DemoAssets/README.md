# Textbook citation demo asset

`OpenStax Organic Chemistry Ch 11 Demo.pdf` is a 20-page excerpt from:

John McMurry, *Organic Chemistry*, OpenStax, 2023.
https://openstax.org/details/books/organic-chemistry

Licensed under CC BY-NC-SA 4.0. The excerpt contains source PDF pages 353–372.
The recorded citation target is local page 6 (source PDF page 358, printed page
346). This asset is included solely for the noncommercial TuberNotes demo.

Build the opt-in demo with the Swift active compilation condition
`TEXTBOOK_CITATION_DEMO`, for example:

```sh
xcodebuild -project TuberNotes.xcodeproj -scheme TuberNotes \
  -configuration Release \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) TEXTBOOK_CITATION_DEMO' \
  build
```

On first launch, that build replaces the notebook library with the prepared
worksheet and textbook and writes a version marker. Later launches preserve
rehearsal edits. Notebook Controls Settings exposes **Reset Citation Demo** to
rebuild the two-notebook state after confirmation. Builds without the condition
do not seed or reset state.
