# PeaversChat

[![Ultra Performance](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/peavers-warcraft/PeaversChat/master/.github/badges/perf.json)](https://github.com/peavers-warcraft/PeaversChat/actions/workflows/perf.yml)
[![AddonSentry](https://addonsentry.io/api/public/repos/peavers-warcraft/PeaversChat/badge.svg)](https://addonsentry.io/dashboard/peavers-warcraft/PeaversChat)

A World of Warcraft addon that redraws the chat window as a flat black box with clean text tabs, puts a copy button where you can see it, and hides every piece of chrome Blizzard hangs around the frame.

Part of the **Peavers Ultra Performance** family: addons that hold themselves to a published budget, measured on every push.

It is meant to be finished out of the box. Install it and chat already looks the way it is supposed to — the settings are there to disagree with, not to assemble.

## Measured performance

Chat is the one part of the UI that never stops, so the claim worth testing is
not that this addon is small — it is that **a chat message costs nothing,
because nothing here is in its way**.

The table below is where that is checked rather than asserted, and the case
behind it fails the build if a message filter is ever installed or the client's
chat handler is ever replaced. It is regenerated on every push by the
[Ultra Performance harness](https://github.com/peavers-code/peavers-warcraft-workflows/tree/master/perf-harness),
which loads this addon's real source into a Lua VM, skins three chat windows,
asks it to re-apply itself two hundred times, then hunts down every `OnUpdate`
handler the addon put on any frame it created and ticks them for a simulated
second. If any number goes outside `perf/budget.json`,
the build fails.

<!-- perf:begin -->

> Measured on every push by the Ultra Performance harness. The build fails if any number here exceeds the budget in `perf/budget.json`.

| Check | Measured | Budget | |
|---|---:|---:|:--:|
| Packaged size | 149.9 KB | 160 KB | pass |
| Bundled libraries | 0 | 0 | pass |
| Widget calls per frame | 0 | 0 | pass |
| Widget calls per second while idle | 0 | 0 | pass |
| Widget calls per second | 21.89 | 30 | pass |

Scenarios driven against the real addon source, outside the game:

| Scenario | Calls/frame | Calls/sec | Notes |
|---|---:|---:|---|
| switching tabs, 1/sec | 0.00 | 21.9 | 22 calls to repaint the whole tab row; 571 calls to skin every window at login, once |
| told to re-apply, 1/sec | 0.00 | 21.0 | 21.0 calls to re-apply the skin to every window when nothing has changed |
| idle, chat on screen | 0.00 | - | 0 OnUpdate handlers installed anywhere in the addon |

<sub>3,880 lines of Lua · 149.9 KB packaged · no bundled libraries</sub>

<!-- perf:end -->

The zeroes are the point, so they are worth explaining:

- **A chat message costs nothing, because nothing here touches one.** No message event filter, no wrapper on a chat frame's `AddMessage`, no replacement of the client's chat handler. The addon draws a background, moves a button and changes a font; a line of chat arrives exactly as it would with the addon uninstalled. The perf case asserts this rather than claiming it.
- **Nothing runs per frame.** There is no `OnUpdate` anywhere in the addon and nothing on a timer. The skin is re-asserted from the events that disturb it — docking, the options panel, a loading screen — not from a ticker checking whether anything moved.
- **The skin is built once.** One backdrop frame per window carrying five textures — a fill and four hairline edges — created the first time the window is seen and afterwards only recoloured and re-anchored.
- **A hidden button costs one event handler.** Buttons are hidden by an `OnShow` hook rather than a poll, so the cost lands only when the client was going to show one anyway.
- **Being told to re-apply costs almost nothing.** The client asks on every visit to the options panel, every dock and undock, and some loading screens. Each module records what it last applied and compares before doing it again, and the measurements a repaint depends on are taken once per pass rather than once per module that wants them. A re-apply that finds nothing changed was 261 client calls; it is now 21, and most of that is asking the client whether anything has moved.

The recurring cost that is not zero is repainting the tab row when you click a
tab, which is measured above at one switch a second — considerably more often
than anybody switches tabs.

## Features

<!-- peavers:features -->
- A flat black chat window with a 1px hairline border, matching the rest of the Peavers UI
- Clean text tabs: no textures, no gold blink, an accent underline on the tab you are reading, in a font of your choosing
- Tabs sit inside the window: the background reaches up over the tab strip rather than stopping underneath it
- Tabs stay readable instead of fading out when the mouse is elsewhere
- A copy mark in the corner of every chat window, costing no layout at all, and a copy window that strips colours, icons and link wrappers back out
- Every button around the frame — chat menu, group finder, scroll arrows, voice, combat log bar — individually hideable, and hidden by default
- The edit box moved out from under the last line of chat, with a border coloured by the channel you are about to speak in
- Channel names abbreviated: `[Guild]` becomes `[G]`, `[Instance Leader]` becomes `[IL]`
- Arrow keys that move the cursor rather than scrolling chat history
- 1000 lines of history kept instead of Blizzard's 128, so the copy button has something to copy
- Adjustable font, size, outline, opacity, padding and colours
- Fully reversible: turning it off hands chat back to Blizzard, with no reload
<!-- /peavers:features -->

## Usage

<!-- peavers:usage -->
Chat is skinned as soon as you log in. Everything else is optional and lives in the settings, under `/pchat`.

Out of the box every button around the chat frame is hidden except the one that jumps to the newest message, the tabs are uppercase text with an accent underline, and there is a small copy mark in the top-right corner of each window — faint until you hover the window, and it takes no space of its own.

### Slash Commands

- `/pchat` - Open settings
- `/pchat copy` - Copy the chat window on top
- `/pchat buttons` - Show or hide every button at once
- `/pchat enable` / `/pchat disable` - Turn the addon on, or hand chat back to Blizzard
- `/pchat reset` - Reset the chat layout to the client's own, then reskin it
- `/pchat safe` - Toggle the channel abbreviations off, so nothing changes what a line says
- `/pchat info` - Print what is currently skinned
- `/pchat style` - Show where each window's background is drawn
- `/pchat channels` - Show what was changed in the channel format strings
- `/pchat trace` - Count chat events as they arrive, then report
- `/pchat defaults` - Put every setting back to its shipped default
<!-- /peavers:usage -->

### Copying

WoW has no clipboard API. The only way text leaves the game is through an edit
box, so the copy window is one: the window's own message buffer poured in and
already selected, waiting for Ctrl+C.

Colours, textures and hyperlink wrappers are taken back out, and what a link was
standing in for stays — an item link copies as its name, not as
`|cffa335ee|Hitem:19019...`. History is raised to 1000 lines from Blizzard's 128
so there is something worth copying.

### Buttons

Everything Blizzard hangs around the outside of a chat window is off by default,
because all of it has a keybind, a slash command or a menu behind it. The one
exception is jumping to the newest message, which has no other way to do it, so
that one stays.

Turning one back on restores what the client had, not what it did not: a
microphone reappears when you are in a voice channel, and a scroll arrow when
there is something to scroll.

### What it deliberately does not do

It does not touch a chat message. At all.

There is no message event filter, no wrapper on a chat frame's `AddMessage`, and
the client's own chat handler is left exactly where it is. A line of chat arrives
the same way it would with this addon uninstalled, and the performance case
asserts that on every push rather than taking it on trust.

That is a deliberate retreat rather than a design principle I started with.
Making URLs clickable means altering the line, three ways of doing it were tried
here, and every one of them was followed by chat failing inside Mythic+. Until
that is understood, the safest chat addon is one that only draws.

The one thing that does change what a line *says* is the channel abbreviation,
and that is a format string the client reads, not a hook in its path — `[Guild]`
becomes `[G]` because the word in the string changed. Numbered public channels
keep Blizzard's own naming: their bracket is assembled per message rather than
read from a string, and taking that over means owning the formatting of every
line in the game.

Class colouring, message routing and channel membership are all left to the
client.

## Installation

### Recommended: PeaversUpdater

Download and install [PeaversUpdater](https://github.com/peavers-warcraft/PeaversUpdater/releases/latest), the desktop updater for the whole Peavers collection. It installs PeaversChat together with its required dependencies and delivers updates before they reach CurseForge.

### Alternative: CurseForge

1. Download from [CurseForge](https://www.curseforge.com/wow/addons/peaverschat)
2. Ensure [PeaversCommons](https://www.curseforge.com/wow/addons/peaverscommons) is also installed
3. Ensure [PeaversConfig](https://www.curseforge.com/wow/addons/peaversconfig) is also installed
4. Enable the addon on the character selection screen

---

*Part of the [Peavers](https://peavers.io) addon collection · [Report an issue](https://github.com/peavers-warcraft/PeaversChat/issues) · [Support development on Patreon](https://www.patreon.com/Peavers)*
