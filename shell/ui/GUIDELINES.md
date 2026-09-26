# Groma UI guidelines

Rules for the shell's surfaces, so the next one does not quietly make a
different decision from the last.

Three lines settle every question of authority:

1. **A rule here is the answer.** Follow it. It was written because the
   question already came up once.
2. **Where this document is silent, the design project decides** - and read it,
   never remember it. `oklch(0.3 0.05 230)` is `#0d3242`, far darker than it
   looks, and a day went on matching that one by eye.
3. **Where the design contradicts a rule here, the rule already won** - that
   contradiction is why the rule exists. Disagree by changing this document,
   never by deviating in a single surface.

Nothing here is a matter of taste at the point of use. If a rule looks wrong,
it is a five-line pull request, not a judgement call in a delegate.


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

Two separate questions, answered separately, so that exactly one answer applies
to any surface.

**The mark in the header.** First row that matches:

| Surface | Header mark |
| --- | --- |
| A later page of a sheet | Back chevron |
| Anything that asks a question | None - the footer answers it |
| An ordinary window | X disc, at the right of its own header |
| Anything else over the whole screen | X disc, top right |
| A bar popup | None - click away, or press its bar icon again |
| A menu at the pointer | None - click away, `Escape`, or `Tab` again |

Never two marks. A back chevron replaces the X; it does not join it.

**The buttons in the footer.** The footer has two slots. On the right, the
answer - first row that matches:

| Surface | Right |
| --- | --- |
| Asks a question you can decline | `Cancel` and the affirmative |
| Asks a question with only one answer | No footer - `Enter` submits |
| Is a search: what you type is the choice | No footer - `Enter` runs the pick; the search track is the header |
| Offers a choice | The affirmative alone |
| Asks nothing | No footer |

On the left, at most one **secondary action** - something other than answering.
`Join Hidden Network…` on the network picker, `Forget` on the Bluetooth one.
This is not a loophole for a second way out: a secondary action does something,
where `Cancel` and the X only leave.

An action that discards saved state takes `variant: "destructive"`. An action
that is merely the main one takes `variant: "primary"`, and there is at most
one of those on a surface.

The affirmative says what it will do to what is selected - `Join Home Wi-Fi`,
`Pair Echo Pop-EX7` - and falls back to the bare verb when nothing is selected,
where it is disabled anyway.

Which puts every surface built so far in exactly one place:

| | Header | Footer |
| --- | --- | --- |
| Volume, battery, Wi-Fi tiles | none | none |
| Network picker | X | `Join Hidden Network…` · `Join` |
| Its join page | back | `Cancel` `Join` |
| Bluetooth tile | none | none |
| Bluetooth devices sheet | X | `Forget` · `Pair`/`Connect` |
| Polkit prompt | none | `Cancel` `Authenticate` |
| Lock screen | none | none - `Enter` submits |
| Launcher | X | none - `Enter` runs the pick |
| Files window | X | none - `Enter` opens the pick; the footer carries the status and the keys |
| Files: a name already taken | none | `Skip` · `Keep both` · `Replace` - three answers, `Escape` is `Skip` |
| Files: a copy in flight | none - a card, not a sheet | `Cancel` alone |

The picker is the one place this overrides the design, which draws a `Cancel`
there as well as the X - two chips side by side doing one thing. Note that the
join page's back and `Cancel` are not that pairing: back returns to the list,
`Cancel` closes the sheet, and they end in different places.

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
- **Convert every colour, never match one by eye.** The desktop base looks like
  a mid slate and is `#0d3242`.
- **A window's corners are 20, not the design's 24.** Hyprland caps its
  rounding at 20, the compositor cuts the corners and blurs the whole window
  rectangle, so the pane has to match it exactly: `Theme.radiusWindow`, and the
  rule in `hypr/hyprland.lua`. Sheets on layer surfaces keep `radiusPanel`.


## Where a thing belongs

| Folder | Holds |
| --- | --- |
| `Theme.qml` | Every colour, metric and type size, named by role. No literals elsewhere. |
| `Settings.qml` | What the user decided. One file in the shell's state directory. |
| `History.qml` | What the user did - launches, counts, times. Its own file there; clearing it never touches a setting. |
| `ui/` | Surfaces and controls with no knowledge of what they show. |
| `icons/` | Glyphs, drawn as `Shape` paths, scaling from a `baseWidth`/`baseHeight`. |
| `modules/` | One feature each: its data, its IPC and its layout. A helper process a module keeps alive is a script beside it, named after it: `files-worker.py`. |
| `integrations/<name>/` | Code for one maker's or one device's behaviour, self-contained. `<name>` is a QML module name: letters only, no hyphens. |

An integration fills a **contract the baseline defines** - a property on a
module (`BluetoothControl.batteryDetail`), a function on a service
(`Osd.say`) - and is instantiated in `shell.qml` in the marked block. That
instance is the only place the baseline refers to it. Dependencies point one
way: an integration may use `ui/`, `icons/`, `Theme`, `Settings` and `Audio`;
nothing in `modules/` imports from `integrations/`. It lives under `shell/`
until an integration needs something that is not shell code - a unit file, a
udev rule - which is the second use that earns a folder at the repo root.

A component is extracted on its **second** use, not in anticipation of one.
