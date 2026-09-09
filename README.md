# PeaversChat

[![Ultra Performance](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/peavers-warcraft/PeaversChat/master/.github/badges/perf.json)](https://github.com/peavers-warcraft/PeaversChat/actions/workflows/perf.yml)
[![AddonSentry](https://addonsentry.io/api/public/repos/peavers-warcraft/PeaversChat/badge.svg)](https://addonsentry.io/dashboard/peavers-warcraft/PeaversChat)

A World of Warcraft addon that redraws the chat window as a flat black box with clean text tabs, puts a copy button where you can see it, and hides every piece of chrome Blizzard hangs around the frame.

Part of the **Peavers Ultra Performance** family: addons that hold themselves to a published budget, measured on every push.

It is meant to be finished out of the box. Install it and chat already looks the way it is supposed to — the settings are there to disagree with, not to assemble.

## Measured performance

Chat is the one part of the UI that never stops. Every line that arrives goes
through whatever filters are installed on it, and on a busy raid night that is
hundreds a minute — so the claim worth testing is that **a chat message costs
the client nothing at all**.

The table below is where that is checked rather than asserted, and the case
behind it also fails the build if the client's own chat handler is ever replaced
or a repaint ever starts happening per combat-log line. It is regenerated on
every push by the
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
| Packaged size | 203.1 KB | 208 KB | pass |
| Bundled libraries | 0 | 0 | pass |
| Widget calls per frame | 0 | 0 | pass |
| Widget calls per second while idle | 0 | 0 | pass |
| Widget calls per second | 24 | 30 | pass |

Scenarios driven against the real addon source, outside the game:

| Scenario | Calls/frame | Calls/sec | Notes |
|---|---:|---:|---|
| chat flowing, 10 messages/sec | 0.00 | 0.0 | 0.00 client calls per message: the matcher is pure string work and never touches a widget |
| switching tabs, 1/sec | 0.00 | 19.9 | 20 calls to repaint the whole tab row; 703 calls to skin every window at login, once |
| combat log flooding, 300 lines/sec | 0.00 | 1.0 | 1 repaint(s) for 3000 combat log lines and 0 for 3000 dock updates: after the first, there is nothing to say |
| told to re-apply, 1/sec | 0.00 | 24.0 | 24.0 calls to re-apply the skin to every window when nothing has changed |
| idle, chat on screen | 0.00 | - | 0 OnUpdate handlers installed anywhere in the addon |

<sub>5,185 lines of Lua · 203.1 KB packaged · no bundled libraries</sub>

<!-- perf:end -->

The zeroes are the point, so they are worth explaining:

- **A chat message costs nothing.** The URL matcher is pure string work, and it bails on a plain substring search before any pattern matching unless the line contains a dot or an at-sign. It never touches a widget, which is why the per-message figure is a flat zero rather than a small number.
- **Nothing repaints per chat line.** The client calls `FCF_StartAlertFlash` for every message arriving in a window that is not on screen — every combat-log line during a pull. Both hooks on that path decide they have nothing to do in a single field read, and the case fails the build if that ever regresses: 3000 combat-log lines cause one repaint, and 3000 dock updates cause none.
- **Nothing runs per frame.** There is no `OnUpdate` installed anywhere in the addon and nothing on a timer. The skin is re-asserted from the events that disturb it — docking, the options panel, a loading screen — not from a ticker checking whether anything moved. The single exception is while you physically drag the optional scroll bar's thumb: that handler goes on at mouse-down and comes off at mouse-up, which is why the hunt below still finds none.
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
- Clickable URLs, with a matcher careful enough not to turn "ok.thanks" into a link
- Tabs sit inside the window: the background reaches up over the tab strip rather than stopping underneath it
- Tabs stay readable instead of fading out when the mouse is elsewhere
- A copy mark in the corner of every chat window, costing no layout at all, and a copy window that strips colours, icons and link wrappers back out
- Every button around the frame — chat menu, group finder, scroll arrows, voice, combat log bar — individually hideable, and hidden by default
- An optional flat scroll bar down the right edge, off by default, and shown only while you hover the window when it is on
- The edit box moved out from under the last line of chat, with a border coloured by the channel you are about to speak in
- Arrow keys that move the cursor rather than scrolling chat history
- 1000 lines of history kept instead of Blizzard's 128, so the copy button has something to copy
- Adjustable font, size, outline, opacity, padding and colours
- Fully reversible: turning it off hands chat back to Blizzard, with no reload
<!-- /peavers:features -->

## Usage

<!-- peavers:usage -->
Chat is skinned as soon as you log in. Everything else is optional and lives in the settings, under `/pchat`.

Out of the box every button around the chat frame is hidden except the one that jumps to the newest message, the tabs are uppercase text with an accent underline, URLs are clickable, and there is a small copy mark in the top-right corner of each window — faint until you hover the window, and it takes no space of its own.

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

### The scroll bar

Off by default. Blizzard's own scrollbar is hidden with the rest of the chrome,
and this draws a flat one in the window's colours instead: a faint track down
the right edge with a thumb whose height is how much of the backlog is on
screen. Drag it, click the track to page, or use the wheel over it as you would
anywhere else in the window.

Once it is on, it shows only while you hover the chat window, which is the
setting it was asked for. "Dimmed until hovered" and "Always" keep it on screen
as a visible control instead, and all three sit under **Scroll Bar** in the
settings, along with its width and colour.

Nothing about it runs per frame, and nothing about it touches the message path
— the thumb moves from the client's own scroll calls, and `AddMessage` is
deliberately left alone. A message arriving while you sit scrolled up nudges the
thumb on your next scroll rather than instantly, which is the right way round for
a chat addon.

### What it deliberately does not do

It does not rewrite the game's chat format strings, and it does not abbreviate
channel names.

That one is worth writing down, because the string it produced always looked
correct. `CHAT_PARTY_GET` is `|Hchannel:party|h[Party]|h %s: `, and shortening
`[Party]` to `[P]` leaves a valid string: same argument count, hyperlink wrapper
intact, only a word changed. But that bracket is the *display text of a
hyperlink*, and the game checks that a hyperlink shows what it is supposed to
show. Messages in every channel whose format string carries such a link stopped
appearing — while `CHAT_SAY_GET`, which is `%s says: ` and has no link in it,
kept working throughout.

Changing a word is not a safe edit when the word is inside a link.

Beyond that, the addon adds to a message and never rebuilds one. URLs are
matched and wrapped by a filter on the client's own chat events, which is the
documented way to alter a line; class colouring, message routing and channel
membership are all left to the client.

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
