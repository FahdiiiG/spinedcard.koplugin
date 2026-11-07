# Changelog

## 1.0.1
- Plugin is now its own plugin: folder `spinedcard.koplugin`, internal name `spinedcard`, shown as "Spined Card" in the plugin list, the Tools menu, the sleep-screen list and the About screen.
- The updater now uses `spinedcard.koplugin` and its own user-agent, so store front / plugin managers no longer match it to the original Book card.
- Internal setting names, cache and gesture action are unchanged, so settings carry over. Do not run it together with the original Book card.

## 1.0.0 — first release of Spined Card
Forked from Book card 1.7.8 (peterboda236); this project starts its own numbering at 1.0.0.

- New: real-book cover (spine, 2–12-line page stack, cover edge, progress ribbon) with full options menu.
- New: two-line progress strip under the cover (chapter | book, pages and bars).
- New: five-star rating box beside the strip.
- New: several whole highlighted quotes per card, reading order, 1–10 lines, reserved space, `Chapter: Name` lines.
- New: cover edge (Off / Thin / Thick) replacing the black/white outline; brightness settings for light and dark cards.
- New: night-mode handling for all new elements; dark-card spine.
- Changed: stat cells (underlined label above value, left-aligned), Started stat date, top row (date left, battery `80% glyph`), side layout (full-width title block), title/author/series rules, quote font regular.
- Removed: Today/Yesterday/N days ago, `{series} / #{index}` template, 5-line quote cap.
- Updater and About now point to this repository.
