# Dashis Dashboard provider cards — design QA

## Comparison target

- Source visual truth: `/private/tmp/codexbar-gui-audit/01-official-codexbar-menu-cropped.png`.
- Source pixels: 363 × 720.
- Source state: CodexBar menu-bar provider surface with Claude selected; one outer usage surface contains the provider header, primary windows and secondary usage, while `Settings…` is a separate utility entry below the data rather than an inline configuration form.
- Intended Dashis Dashboard state: app default 1160 × 760 window with Dashboard selected; the Codex card contains the synthetic 5-hour and 7-day windows while the remaining enabled providers show honest no-data states. The dashboard uses one system outer card per enabled provider, an adaptive two-column/one-column layout, and no configuration controls.
- Intended Dashis detail state: Debug `--visual-qa` Codex display page containing the same two main windows, secondary credits and warning, with no configuration form or action controls.
- Intended Dashis settings state: top-level Settings selected, the searchable second-level menu still contains all 34 providers, every row has a native system switch controlling Dashboard/main-Sidebar visibility, Codex is selected, and its native grouped configuration form is shown in the right pane.
- Intended fidelity scope: CodexBar's one-provider/one-outer-surface composition, main-usage-first hierarchy and restrained separators. Dashis applies that hierarchy to a native dashboard card grid and the full provider detail card while retaining its existing macOS `NavigationSplitView`, protected Serif brand and native grouped controls. CodexBar's menu tabs, wallpaper, menu commands and provider icons are not implementation targets. The Settings workspace follows the user's explicit information-architecture requirement rather than copying the CodexBar menu image.

## Evidence

- Source image opened and inspected: yes.
- Implementation screenshot: available for the pre-fix Settings regression. A post-fix reduced native `NSHostingView` structural render is also available in the current temporary workspace; no full post-fix Dashis App screenshot yet.
- Implementation screenshot path: intentionally not persisted in the repository because both the supplied capture and reduced probe are temporary local evidence.
- CSS viewport: not applicable; this is a native SwiftUI macOS app.
- Intended implementation viewport: 1160 × 760 points at the system display density.
- Implementation pixel dimensions and density normalization: supplied canvas is 2544 × 1744 pixels; the Dashis window occupies approximately 2320 × 1520 pixels, matching the 1160 × 760-point default size at 2× density.
- Full-view comparison evidence: the supplied Settings capture is sufficient to diagnose the window-shell regression. The reduced post-fix native probe verifies the 218/220 column geometry and intact leading edges, but it does not contain the complete App state and cannot establish Dashboard or provider-display fidelity.
- Focused-region comparison evidence: the pre-fix captures cover the real primary Sidebar, collapsed Settings provider Sidebar and Kimi form. The reduced post-fix probe covers the final single-split structure with long provider names, search and native switches; Dashboard cards, the Codex detail card and the complete corrected App shell remain uncaptured.

## Source-level review

The implementation now has three deliberately separate surfaces. Dashboard uses a centered adaptive `LazyVGrid`: each currently enabled provider has one system `GroupBox` card, the grid is two columns when the content width allows and one column when it does not, and the whole card only opens the provider display page. There are no action buttons or configuration sections on the Dashboard. A no-data card shows the provider name and honest primary empty state. A populated card reuses `ProviderVisualizationProjection` and exposes at most two primary metric panes; 5-hour/7-day windows remain first, and a real balance remains first when there are no windows. The compact card omits metadata and long notice bodies so it does not become a settings or diagnostics surface. When every provider is disabled, Dashboard uses the system `ContentUnavailableView` and points back to Settings.

Direct provider navigation opens a data `ScrollView` containing one fuller system `GroupBox`. It uses the same primary projection, then keeps additional usage plus source/scope/observed metadata in disclosures inside that one card. Warnings and partial failures remain visible inside the detail card without acquiring their own surfaces.

The main Sidebar has one text-only Settings entry and no search field; it only receives the enabled-provider projection. Two real 1160 × 760 captures disproved the nested Settings `NavigationSplitView`: the first clipped the leading edge of the brand and every navigation row, while the second retained the primary misalignment, collapsed the entire Settings provider column and exposed a top-right restoration chevron. The final source keeps exactly one outer `NavigationSplitView`, locks its primary Sidebar to 218 points, and builds Settings as a non-collapsible 220-point `NSSearchField` plus system `.inset` List/switch panel beside the flexible Form. Both sets of labels remain compressible and tail-truncated. The full 34-provider catalog, visibility persistence, real native/collector forms and backend are otherwise unchanged.

The supplied screenshot establishes the pre-fix failure. The source review and successful compilation establish what changed afterward, but they are not post-fix visual evidence and cannot establish final fidelity.

## Required fidelity surfaces

- Fonts and typography: source target uses a compact system hierarchy; Dashboard source uses system `headline`, `title2`, `subheadline`, `caption2` and `footnote`, while the detail source uses `title3`, `headline`, `largeTitle`, `title3`, `subheadline` and `footnote`. Actual optical size, wrapping and antialiasing are unverified.
- Spacing and layout rhythm: source target uses one outer card and separators; Dashboard source uses a 16-point adaptive grid, 350–520-point tracks, 28-point page margins, one `GroupBox` per enabled provider and one divider between identity and data. The detail source uses one `GroupBox`, 14/12-point section spacing and two responsive panes. Settings uses a fixed 220-point native search/`.inset` List panel, a passive Divider, trailing system switches and a flexible grouped Form inside the only outer split; the primary Sidebar is independently locked to 218 points. Provider text compresses and truncates while the system switch stays fixed-size. Actual post-fix grid track count at 1160 × 760, row-height consistency, switch/text fit for long provider names, card insets and vertical density are unverified.
- Colors and visual tokens: implementation uses system semantic foregrounds, the default system `GroupBox` surface and semantic progress/status colors. Actual light/dark appearance and contrast are unverified.
- Image quality and asset fidelity: the targeted Dashboard and detail cards contain no app-specific raster assets. Dashis intentionally does not reproduce CodexBar's provider icon strip or wallpaper and does not replace them with generic symbols.
- Copy and content: the synthetic Dashis state uses `Codex`, actual projected window labels and truthful source/scope/freshness labels. The implementation does not copy CodexBar's provider-specific Claude plan or utility commands.

## Findings

- [P1] No post-fix or Dashboard/detail rendered evidence
  - Location: corrected Dashis window shell, Dashboard card grid and Codex display page.
  - Evidence: the supplied Dashis screenshot captures the pre-fix Settings failure, but no screenshot exists for the corrected build or the matching Dashboard/detail trial states.
  - Impact: the leading-edge repair, adaptive track count, provider-card proportions, empty/populated row-height consistency, two-pane density, typography, fixed secondary-menu width, native-switch alignment/hit targets, long-name fit, grouped-form rhythm and light/dark behavior cannot yet be judged after the fix.
  - Fix: when foreground visual QA is explicitly allowed, capture the 1160 × 760 Dashboard with the synthetic Codex data, the Codex detail page and Settings → Codex in light and dark appearance, including one provider switched off and back on, then compare the matching card/menu regions with the source in one combined image.

- [P0] Primary Sidebar leading edge clipped in the default window — fixed in source, awaiting post-fix capture
  - Location: the complete primary Sidebar in the supplied Settings screenshot.
  - Evidence: `Dashis`, `Dashboard`, `Settings`, the Providers section label and every provider name lose their leading characters at the same window boundary; the 1160-point window still has ample right-side space, ruling out an undersized window.
  - Cause: nested navigation containers owned competing restoration/column state; width constraints alone did not remove that state.
  - Fix: keep one outer split, lock its primary Sidebar to 218 points, replace the nested Settings split with a fixed 220-point detail panel, assign fresh List identities, and keep labels explicitly compressible/tail-truncated.

- [P0] Settings provider column collapsed and generated a restoration chevron — fixed in source, awaiting full post-fix capture
  - Location: the second supplied Settings screenshot.
  - Evidence: the entire 220-point provider menu is absent while the Kimi Form remains; a large double chevron appears in the top-right toolbar, proving the inner navigation container entered a collapsed column state.
  - Fix: remove the inner `NavigationSplitView` entirely. A fixed detail panel has no column visibility, toolbar toggle or draggable split divider.

## Open questions

- Whether the locked 220-point Settings provider panel and native `NSSearchField` have the right optical width and vertical rhythm inside the corrected 218-point primary shell.
- Whether long provider names and the trailing small system switch remain optically clear at the locked 220-point width.
- Whether the 350–520-point adaptive Dashboard tracks produce the desired two-column density at the real default window size.
- Whether the compact Dashboard metric panes need slightly less height after viewing the real 1160 × 760 composition.
- Whether no-data Dashboard cards should remain the same row height as populated cards after the first visual comparison.

## Comparison history

- Iteration 1: replaced separate primary `GroupBox` cards and separate usage/detail sections with one top-level system provider card; moved additional usage, metadata and notices into that card without nesting new surfaces.
- Iteration 2: removed every configuration/action section from provider display pages and every action button from Dashboard rows; added one top-level Settings entry with a searchable second-level 34-provider menu and moved the existing real grouped forms there.
- Iteration 3: replaced the degraded Dashboard summary rows with 34 unified system `GroupBox` provider cards in an adaptive two-column/one-column grid. Each card now reuses the real primary data projection, prioritizes two actual subscription windows or one actual balance, and keeps settings/metadata out of the compact surface.
- Iteration 4: removed search from the main Sidebar and added a native trailing switch to every row of the complete Settings provider catalog. Dashboard and main Sidebar now share the persisted enabled-provider projection; hiding never removes the Settings row, data or configuration.
- Iteration 5: removed the nested Settings column-width preference and the switch row's explicit horizontal spacing/minimum Spacer. Provider text is now the only compressible child and truncates within the width already assigned by the system; the native switch remains fixed-size, so row content no longer asks the outer split view to redistribute the protected main Sidebar.
- Iteration 6: attempted to remove the nested Settings `NavigationSplitView` and replace it with a fixed 220-point `HStack`, passive `Divider` and AppKit `NSSearchField`. It was reverted after an incomplete source-only diagnosis; the later real captures showed that the nested split and stale List state, not the absence of an inner navigation container, were the persistent failure mode.
- Iteration 7: reverted the fixed manual shell and restored the native Settings `NavigationSplitView`; removed its explicit column-width modifier, removed forced `.balanced` style from both split views, kept provider text compressible/truncated and the switch fixed-size, and normalized a persisted top-level Settings selection back to Dashboard at launch. The subsequent real screenshot showed this was still insufficient because the primary Sidebar itself could be compressed below its ideal layout width.
- Iteration 8: used the supplied default-window screenshot as runtime evidence, centralized window metrics, locked the primary and Settings Sidebar widths to 218 and 220 points respectively, and made every primary navigation row explicitly compressible. A first reduced native render exposed that the inner width modifier was inside the `.searchable` wrapper and therefore fell back to about 145 points; moving it after `.searchable` and `navigationTitle` produced the intended 220-point secondary column with intact long labels and switches. Final silent `build-for-testing` passed.
- Iteration 9: the second real screenshot showed that fixed widths still cannot make a nested split stable under real window restoration. Removed the inner split and its column visibility entirely; Settings now uses a fixed 220-point native search/`.inset` List/switch panel inside the only outer detail. A reduced offscreen `NSHostingView` render confirmed complete primary/secondary leading edges, simultaneous panel/Form visibility and no second navigation toggle; final silent `build-for-testing` passed.
- Iteration 10: removed persistent method, access, credential-lifecycle and risk explanations from all provider settings. Collector consent now appears only in the action-time alert; native-provider explanatory footers and Recent Calls onboarding copy were removed while real status/error/truncation content and destructive-action confirmations remain. Final incremental `build-for-testing` passed.
- Post-fix visual evidence: the reduced offscreen native single-split structural probe passed. A complete post-fix Dashis App screenshot remains unavailable because Dashis was no longer running and was deliberately not relaunched.

## Implementation checklist

- Capture the 1160 × 760 Dashboard with the synthetic Codex state, the Debug `--visual-qa` detail state, and Settings → Codex without using real provider credentials.
- Compare the full Dashboard and focused populated/no-data card crops, then the detail-card crop, against the source visual in combined images.
- Verify Dashboard cards and provider display pages contain no settings/actions; all 34 providers remain selectable in the Settings secondary menu; switching one off removes exactly its Dashboard card and main-Sidebar row, and switching it on restores both without losing data.
- Fix any P0/P1/P2 typography, spacing, wrapping or surface-nesting mismatch.
- Re-capture at the same viewport and record the final comparison here.

## Follow-up polish

- Decide after the first visual capture whether the Dashboard track minimum should move slightly above or below 350 points and whether the detail-card header should keep long scope labels on the right. Do not widen the Settings secondary column or add horizontal row padding to solve name/switch spacing; long names must truncate within the system-assigned width.

final result: blocked
