# Core Dev Tools

A local-only native macOS app for common developer tasks. It is built directly with Apple's Swift command-line toolchain: no Xcode project, package manager, developer account, external dependency, or network request.

## Features

- Multi-editor JSON Formatter with in-place Beautify and Minify actions
- Per-editor indentation using 2 spaces (default), 4 spaces, or tabs
- Read-only side-by-side JSON diff with aligned wrapping, line numbers, change highlights, difference counts, and jump navigation
- Bidirectional JSON ↔ JSON string literal converter
- Bidirectional URL percent encoder and decoder
- Native word-wrapped JSON editors with syntax highlighting and macOS Find (`⌘F`)
- Browser-style tabs with drag-to-reorder and middle-click-to-close; every app launch starts fresh
- System, Light, and Dark appearance modes with automatic preference restore

Object keys are compared independent of their source order. Comparison lines follow the
order in JSON 1; keys found only in JSON 2 are appended in their JSON 2 order.
Arrays of objects are aligned by a stable identity field when every element on
both sides is an object that carries the same recognized field, that field's
values are unique within each array, and the two arrays share at least one value.
The recognized fields, in priority order, are `id`, `uuid`, `guid`, `key`,
`code`, `codes`, `slug`, and `name`. All other arrays use value-aware positional
alignment. Duplicate object keys are rejected because their meaning would be
ambiguous in an exact key-based comparison.

## Build

Install the Xcode Command Line Tools once if needed:

```sh
xcode-select --install
```

Then build and open the app:

```sh
./build.sh
open "Core Dev Tools.app"
```

`build.sh` compiles for the current Mac architecture, assembles the `.app`
bundle, and applies an ad-hoc signature. It targets macOS 13 or newer and is
intended for use on the Mac that built it.

## Tests

```sh
./test.sh
```

Tabs and editor contents are intentionally kept in memory only and are discarded
when the app quits. Only the lightweight appearance preference is retained.

## License

Released under the [MIT License](LICENSE) — free to use, modify, and distribute.
