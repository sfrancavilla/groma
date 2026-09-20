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

Two buttons that do the same thing say the same words. Where one of them has
less room, **drop the verb, never change the noun**: the network sheet's
`Join Hidden Network…` is the tile's `Hidden Network…`, not `Join by name`.
A label that will not fit is a `DialogButton` concern - it elides - not a
reason to invent a synonym.

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
leaving without choosing anything is a normal outcome rather than a refusal -
and for the same reason it gets **no `Cancel`**, which would be that second way
to say no. The design draws both on the network picker; the rule wins here,
because on screen the two chips sat side by side doing the same thing.

A later page of a sheet may still carry `Cancel` alongside its back chevron.
Those are not two ways to say no: back returns to the previous page, `Cancel`
closes the sheet. The join page has both, correctly.

There is **one** close mark: `ui/DiscButton.qml`, `glyph: "close"`. Not a text
`×`, which renders at whatever the font decides and cannot be hit reliably.
Its marks scale with the button, so a toast's 20px close and a sheet's 36px one
are the same control at two sizes. Pass `markColor` where the surface resolves
its own text colour, as the notification toast does from urgency.

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


## Known deviations

None outstanding. The three this document was written to surface - two
spellings of one action, two ways of drawing a close mark, and a picker
carrying both an X and a `Cancel` - are fixed, and the rules above say which
way each went.

Add to this list rather than to the rules when something has to differ for a
reason. A deviation that is written down is a decision; one that is not is how
the three above happened.
