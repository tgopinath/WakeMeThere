# Wake Me There: Apple HIG components audit

Audited 2026-11-17 against Apple's Human Interface Guidelines, Components
(https://developer.apple.com/design/human-interface-guidelines/components), on iOS 26.1 Simulator (iPhone 17 Pro).
Checked in light, dark and Accessibility Extra Large text, using the DEBUG `-demo [trip|ring|undo|trips|add|edit]` states.

Status: **Fixed**, **Kept** (already follows the HIG, no change needed) or **Open** (not done yet).

## Already in line with the HIG (Kept)

| Area | What the app does |
|---|---|
| Tab bar | Stock `TabView` with two SF Symbol tabs (Stops, Trips). |
| Navigation bars | Large titles on both tabs; `EditButton` leading, Add (`plus`) as the primary action. |
| Lists | Inset-grouped `List` with section headers and footers. |
| Swipe actions | Trailing Delete (destructive, full swipe) and Edit; leading Start. Context menu repeats them. |
| Confirmation dialogs | Delete stop, Clear history and End trip all use `confirmationDialog` with a destructive role. |
| Search | `.searchable` in the stop sheet, navigation-bar drawer, always shown. |
| Sheets | Add/Edit stop is a sheet with Cancel (cancellation action) and Save (confirmation action, disabled until valid). |
| Empty state (Trips) | `ContentUnavailableView`. |
| Progress | Stock `ProgressView` for trip progress. |
| Full-screen alarm | `fullScreenCover`, dismissed only by "I'm awake" or Snooze, as an alarm should be. |
| Colour | Accent from the asset catalog; system label, fill and background colours elsewhere. |

## Findings and fixes

| # | Screen | Finding | Fix | Status |
|---|---|---|---|---|
| 1 | Stop sheet | Settings were a custom panel (hand-styled text field, custom capsule preset buttons about 26pt tall, its own Delete link). It did not scroll, so large text squashed the map. | Rebuilt as a stock inset-grouped `Form`: map row, Name section, Alarm distance section (`LabeledContent` + `Slider` with min/max labels + segmented quick-pick `Picker`), a Save & start button row, and a destructive Delete row in its own section. | Fixed |
| 2 | Stop sheet | Slider had no accessible label or value. | Added the "Alarm distance" label and the distance as its value. | Fixed |
| 3 | Stops | Empty state was a custom row. | `ContentUnavailableView` with a prominent "Add a stop" action. | Fixed |
| 4 | Stops | Start button used `.controlSize(.small)`, under the 44pt minimum tap target. | Regular size, plus a VoiceOver label ("Start trip to …"). | Fixed |
| 5 | Stops | At accessibility text sizes the name was cut to one line and the distance metadata ran together. | Row switches to a vertical layout: the icon tile hides, the name wraps to three lines, the metadata stacks, and Start sits below. Icon tile size follows `@ScaledMetric`. | Fixed |
| 6 | Stops, Trips | VoiceOver read decorative icons and split each row into several elements. | Icons hidden; each row reads as one combined element. | Fixed |
| 7 | Undo toast | The Undo target was smaller than 44pt; the toast disappeared after 4 s without telling VoiceOver; it always slid in. | 44pt Undo button with a clear label, a spoken announcement, 10 s on screen when VoiceOver is running (5 s otherwise), and a fade instead of a slide with Reduce Motion. A border is added under Increase Contrast. | Fixed |
| 8 | Trip | The distance used a fixed 44pt font, so it ignored Dynamic Type. The panel could not scroll and overflowed at large sizes. | Large Title text style (rounded, bold). The panel scrolls only when it doesn't fit (`ViewThatFits`). At accessibility sizes the Armed badge moves under the name and the metadata stacks. | Fixed |
| 9 | Trip | The "HEADING TO" all-caps eyebrow, and the progress bar had no label. | Sentence case "Heading to". The stop name is marked as a header, the progress bar is labelled "Trip progress", and the badge reads "Alarm armed" or "Alarm snoozed". | Fixed |
| 10 | Trip | The material panel loses contrast over busy maps when Increase Contrast is on. | Solid system background with a hairline border under Increase Contrast. | Fixed |
| 11 | Alarm | The gradient's light orange end gave white text a contrast of about 2.7:1, failing WCAG AA. | The gradient is deeper (about 3.9:1, which passes for this large text), and darker still under Increase Contrast. | Fixed |
| 12 | Alarm | The pulsing rings and the symbol animation ignored Reduce Motion. The fixed 48pt title ignored Dynamic Type. VoiceOver got no announcement. | Rings and symbol effect turn off with Reduce Motion. The title uses Large Title style and is marked as a header. A "Wake up" announcement is posted. | Fixed |
| 13 | Animations | Camera fly-to, radius presets and the distance counter animated even with Reduce Motion on. | Animations are skipped when Reduce Motion is on. | Fixed |
| 14 | Colour | The accent had no Increase Contrast variant. | Added high-contrast light (#453CD1) and dark (#A8A4FF) accent variants. | Fixed |
| 15 | Debug | There was no way to screenshot the stop sheet. | Added DEBUG `-demo add` and `-demo edit`. | Fixed |
| 16 | Trip | The trip screen is a custom panel over the map rather than a sheet with detents, which is the pattern Apple Maps uses. Moving it to a sheet clashes with the alarm's `fullScreenCover`, because SwiftUI can present only one modal at a time from the root. | Left as a floating panel. Revisit by presenting the alarm from the trip sheet. | Open |
| 17 | Stops | Tapping the row itself does nothing; only the Start button and swipe actions do. | Could open Edit on tap. Left alone so a stray tap can't open a sheet mid-commute. | Open |

## Screenshots

The refreshed portfolio shots, light mode, are in `prototype/shots/`: home, trips, undo, trip and ring (`.jpg`).
