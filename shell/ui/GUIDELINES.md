# Groma UI guidelines

Rules for the shell's surfaces. Most of these are not preferences - they are
decisions already made in `Theme.qml` and in the design project, written down
so the next surface does not quietly make a different one.

Where a rule and the design disagree, the design wins and the rule gets
amended. Where a rule and a *guess about* the design disagree, read the CSS.


## Capitalisation

**Title Case** names a surface: tile titles, sheet titles, and a button whose
label is the surface it opens.

> Sound · Battery · Wi-Fi · Other Networks · Join Hidden Network ·
> Authentication Required

**UPPERCASE** labels the group of controls directly below it, and nothing else.
It is a structural marker, not emphasis.

> NETWORK NAME · PASSWORD · SECURITY · OTHER NETWORKS

Never uppercase something that carries its own casing - a unit, a standard, a
trademark. `2.4 GHZ` and `WI-FI` are wrong. This is why the band headings in
the network picker are `5 GHz` and `2.4 GHz` although they sit in the same slot
as an uppercase label.

**Sentence case** is everything else: body copy, captions, switch and checkbox
labels, and buttons that act.

> Remember this network · Public address · Wi-Fi radio ·
> Clear the search to see all. · Cancel · Join

Captions that are full sentences take a full stop. Fragments do not.

An **ellipsis** - the character `…`, never three periods - marks a label that
opens a further step instead of acting. `Join Hidden Network…` opens a form;
`Join` joins. `Joining…` is the exception: there, it marks work in progress.


## Getting out

Which dismissal a surface offers follows from what kind of surface it is.

| Surface | Way out |
| --- | --- |
| Bar popup (a tile under its bar icon) | None drawn. Click away, or the icon again. |
| Prompt (asks a question) | Its answer buttons. `Cancel` and the affirmative. No X. |
| Browse surface (offers things to look at) | An X disc, top right. |
| Page of a multi-page sheet | Back chevron **in place of** the X, never both. |

A prompt gets no X because `Cancel` already is one, and two ways to say no
invites the question of whether they differ. A browse surface gets an X because
leaving without choosing anything is a normal outcome rather than a refusal.

There is **one** close mark: `ui/DiscButton.qml`, `glyph: "close"`. Not a text
`×`, which renders at whatever the font decides and cannot be hit reliably.

Any surface that takes the keyboard exclusively - a lock screen, a modal sheet -
**must** also be dismissable by `Escape` *and* by an IPC call. A keyboard grab
with a bug in it locks the user out of their own session, and the chat window
they would ask for help in is behind it.


## Drawing on this display

The panel is 2880×1920 at scale 2, so one logical pixel is two physical ones.

- **No 1px inset highlights.** A highlight drawn just inside a 1px border lands
  on adjacent physical pixels and reads as a doubled line. This had to be taken
  out of `GlassPanel` once and out of `NetworkRow` before it went in.
- **Rings, not thicker borders**, for focus and selection. A border that grows
  when a thing is focused nudges everything beside it. See `GlassField` and the
  selected state in `NetworkRow`.
- A ring is drawn *outside* its element, so **do not clip a container** that
  holds focusable or selectable children - it will shave the rings off. Where
  clipping is unavoidable, inset the content by the ring's width instead. Both
  the picker's row column and its page slide are built around this.
- **Never eyeball a colour from the design.** `oklch(0.3 0.05 230)` is `#0d3242`,
  far darker than it looks, and a session was lost to guessing it. Convert it.


## Where a thing belongs

| Folder | Holds |
| --- | --- |
| `Theme.qml` | Every colour, metric and type size, named by role. No literals elsewhere. |
| `ui/` | Surfaces and controls with no knowledge of what they show. |
| `icons/` | Glyphs, drawn as `Shape` paths, scaling from a `baseWidth`/`baseHeight`. |
| `modules/` | One feature each: its data, its IPC and its layout. |

A component is extracted on its **second** use, not in anticipation of one.


## Open and inconsistent

Known deviations. Each is either a decision waiting to be made or a small fix.

- **The network picker has both an X and `Cancel`**, which by the rule above is
  one too many. The design draws both, so the rule may be wrong rather than the
  screen. Undecided.
- **`NotificationToast` closes with a text `×`** rather than a `DiscButton`. It
  predates the component. A disc is too heavy for a toast's corner, so this
  probably wants a small `DiscButton` size rather than a different mark.
- **The same action is named twice**: `Join by name` on the Wi-Fi tile,
  `Join Hidden Network…` in the sheet it opens.
