# Dashis shell restoration and Codex usage hierarchy — visual QA

## Source truth

- Dashis shell source: `/private/tmp/dashis-font-source-normalized.png`, a temporary normalized copy used only for local comparison. The user-supplied source image and its account values were not copied into the repository.
- Codex hierarchy source: the user-supplied Codex Analytics screenshot, used only to establish information priority, two-column quota cards, progress treatment, and the placement of secondary details.
- Target: restore the established Dashis shell exactly enough that typography, sidebar rhythm, selection treatment, title origin, and content width read as the original product; keep only the requested provider visualization improvements inside that shell.
- Deliberate difference from the old Dashis content: the raw equal-weight key/value table stays replaced by typed quota cards, verified progress, one concise warning, and collapsed secondary data.

## Rendered implementation

- Final implementation screenshot: `/private/tmp/dashis-shell-restored-final.png`
- Original Dashis full-view comparison: `/private/tmp/dashis-shell-source-comparison-full.png`
- Original Dashis focused comparison: `/private/tmp/dashis-shell-source-comparison-focus.png`
- Codex hierarchy full-view comparison: `/private/tmp/dashis-shell-codex-comparison-full.png`
- Codex hierarchy focused comparison: `/private/tmp/dashis-shell-codex-comparison-focus.png`
- Viewport: 1162 × 768, light appearance, Codex provider route.
- State: Debug-only `--visual-qa` synthetic snapshot; it does not read account files, credentials, or network data.

## Iteration history

1. The first redesign replaced the raw provider table with typed quota cards, a two-column balance grid, progress bars, and collapsed details.
2. Visual review fixed density issues: three equal cards in one row became two columns, credits moved to the second row, repeated explanatory copy was removed, and warning treatment was reduced.
3. User review exposed a P1 identity regression: the Codex reference had been treated as permission to replace Dashis typography. The serif brand and title family were restored.
4. A second user review exposed another P1 regression: restoring only the font family still left the shell effectively rewritten. Brand size and position, page-title size and origin, sidebar row cadence, selection treatment, content padding, and content width were all still wrong.
5. The original Dashis screenshot was normalized to the same viewport and compared beside the implementation. The shell was restored to a 28 pt brand, 32 pt page title, 176/218 sidebar sizing, approximately 14 pt serif navigation with approximately 40 pt provider cadence, inset light-blue selection, 30/26/30 detail padding, 14 pt stack spacing, 900 pt provider width, and 1180 pt outer width.
6. The final focused comparison confirms the brand and title origins, navigation baselines, provider row cadence, and selected-row bounds now align with the original shell. The Codex comparison confirms that only the information hierarchy—not Codex branding—was adopted.

## Final comparison

| Area | Result |
| --- | --- |
| Fonts and typography | Passed — the 28 pt Dashis brand, 32 pt page title, serif navigation face, weights, and primary numeric hierarchy match the intended sources. |
| Spacing and layout | Passed — sidebar width, brand origin, title origin, approximately 40 pt navigation cadence, inset selection, 30/26/30 detail padding, 14 pt vertical rhythm, 900 pt provider width, and 1180 pt outer width were verified in side-by-side inputs. |
| Colors and tokens | Passed — the original quiet sidebar and light-blue selected row are restored; cards use white surfaces, low-contrast strokes, restrained shadows, green verified progress, and orange warning semantics. |
| Assets | Passed — all visible icons remain native SF Symbols; no placeholder, handcrafted SVG, or substitute raster asset was introduced. |
| Copy and content | Passed — quota labels, reset text, warning, disclosures, and native actions are concise and not duplicated. |
| Visualization | Passed — real Codex windows are represented as typed cards; no obsolete five-hour window is invented; unknown progress remains absent; only the visual fill is clamped. |
| Interaction and accessibility | Passed — provider navigation remains clickable with selected-state accessibility output, quota cards expose grouped labels and values, and refresh, clear, and disclosure controls remain available. |

No open P0, P1, or P2 visual issues remain in the checked synthetic state.

final result: passed
