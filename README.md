# PeaversChat

[![Ultra Performance](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/peavers-warcraft/PeaversChat/master/.github/badges/perf.json)](https://github.com/peavers-warcraft/PeaversChat/actions/workflows/perf.yml)
[![AddonSentry](https://addonsentry.io/api/public/repos/peavers-warcraft/PeaversChat/badge.svg)](https://addonsentry.io/dashboard/peavers-warcraft/PeaversChat)

A World of Warcraft addon that redraws the chat window as a flat black box with clean text tabs, turns URLs into something you can click, puts a copy button where you can see it, and hides every piece of chrome Blizzard hangs around the frame.

Part of the **Peavers Ultra Performance** family: addons that hold themselves to a published budget, measured on every push.

It is meant to be finished out of the box. Install it and chat already looks the way it is supposed to — the settings are there to disagree with, not to assemble.

## Measured performance

Chat is the one part of the UI that never stops. Every line that arrives goes
through whatever filters are installed on it, and on a busy raid night that is
hundreds a minute — so the claim worth testing is not that this addon is small,
it is that **a chat message costs the client nothing at all**.

It does not, and the table below is where that is checked rather than asserted.
It is regenerated on every push by the
[Ultra Performance harness](https://github.com/peavers-code/peavers-warcraft-workflows/tree/master/perf-harness),
which loads this addon's real source into a Lua VM, skins three chat windows,
pushes four hundred messages through the filter that is actually installed, then
hunts down every `OnUpdate` handler the addon put on any frame it created and
ticks them for a simulated second. If any number goes outside `perf/budget.json`,
the build fails.

<!-- perf:begin -->

> Measured on every push by the Ultra Performance harness. The build fails if any number here exceeds the budget in `perf/budget.json`.

| Check | Measured | Budget | |
|---|---:|---:|:--:|
| Packaged size | 157 KB | 160 KB | pass |
| Bundled libraries | 0 | 0 | pass |
| Widget calls per frame | 0 | 0 | pass |
| Widget calls per second while idle | 0 | 0 | pass |
| Widget calls per second | 33 | 60 | pass |

Scenarios driven against the real addon source, outside the game:

| Scenario | Calls/frame | Calls/sec | Notes |
|---|---:|---:|---|
| chat flowing, 10 messages/sec | 0.00 | 0.0 | 0.00 client calls per message: the URL matcher is pure string work in an AddMessage hook, and never touches a widget |
| switching tabs, 1/sec | 0.00 | 33.0 | 33 calls to repaint the whole tab row; 796 calls to skin every window at login, once |
| idle, chat on screen | 0.00 | - | 0 OnUpdate handlers installed anywhere in the addon |

<sub>4,074 lines of Lua · 157 KB packaged · no bundled libraries</sub>

<!-- perf:end -->

The zeroes are the point, so they are worth explaining:

- **A chat message costs nothing.** The URL matcher is pure string work, and it bails on a plain substring search before doing any pattern matching unless the line contains a dot or an at-sign. It never touches a widget, which is why the per-message figure is a flat zero rather than a small number.
- **Nothing runs per frame.** There is no `OnUpdate` anywhere in the addon and nothing on a timer. The skin is re-asserted from the events that disturb it — docking, the options panel, a loading screen — not from a ticker checking whether anything moved.
- **The skin is built once.** One backdrop frame per window carrying five textures — a fill and four hairline edges — created the first time the window is seen and afterwards only recoloured and re-anchored.
- **A hidden button costs one event handler.** Buttons are hidden by an `OnShow` hook rather than a poll, so the cost lands only when the client was going to show one anyway.

The recurring cost that is not zero is repainting the tab row when you click a
tab, which is measured above at one switch a second — considerably more often
than anybody switches tabs.

## Features

<!-- peavers:features -->
- A flat black chat window with a 1px hairline border, matching the rest of the Peavers UI
- Clean text tabs: no textures, no gold blink, an accent underline on the tab you are reading, in a font of your choosing
- Tabs sit inside the window: the background reaches up over the tab strip rather than stopping underneath it
- Tabs stay readable instead of fading out when the mouse is elsewhere
- Clickable URLs, with a matcher careful enough not to turn "ok.thanks" into a link
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

Out of the box every button around the chat frame is hidden except the one that jumps to the newest message, the tabs are uppercase text with an accent underline, URLs are clickable, and there is a small copy mark in the top-right corner of each window — faint until you hover the window, and it takes no space of its own.

### Slash Commands

- `/pchat` - Open settings
- `/pchat copy` - Copy the chat window on top
- `/pchat buttons` - Show or hide every button at once
- `/pchat enable` / `/pchat disable` - Turn the addon on, or hand chat back to Blizzard
- `/pchat reset` - Reset the chat layout to the client's own, then reskin it
- `/pchat info` - Print what is currently skinned
<!-- /peavers:usage -->

### Clickable URLs

The hard part is not finding URLs. It is not finding things that are not URLs.

Chat is full of text that looks like a domain if you squint — "ok.thanks",
"trust.me", "3.5" — and a chat window that turns every other sentence into blue
brackets is worse than one that does nothing at all. So the matcher works one
whitespace-separated word at a time rather than running patterns over the whole
message, which is where every homegrown URL matcher eventually eats an item
link. Three rules do the work:

- A word containing a pipe is skipped outright. That is every item link, spell, achievement, colour run and texture escape the client can emit, ruled out in one test.
- Anything with a scheme, a `www.`, an `@` or a path is taken at face value.
- A bare host with none of those has to end in a top-level domain from a short list — and that list deliberately leaves out the country codes that are also English words. `.no`, `.me`, `.it` and `.us` are not on it, because "yeah.no" is not a website.

Clicking a link opens the copy window with the address selected. An addon cannot
open a browser, so click, Ctrl+C, Escape is as close as the game gets.

The matching happens on the line's way to the screen, in a hook on each chat
frame's own `AddMessage`, rather than in a `ChatFrame_AddMessageEventFilter` on
the way in. That is not a stylistic choice. The filter version stopped chat
working in instanced content: authored messages never appeared while system
messages, which take a different path, arrived normally. The event path is where
the client does its restricted-data handling, and an addon standing in the
middle of it is standing somewhere it no longer has any business being. By the
time a line reaches `AddMessage` the client has finished with it and what
arrives is text.

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

It does not take over how a chat line is built.

Numbered public channels keep Blizzard's own naming. Their bracket is assembled
from the channel list at message time rather than read from a format string, so
abbreviating them means replacing `ChatFrame_MessageEventHandler` and owning the
formatting of every line in the game. That is how a chat addon ends up needing a
fix on every patch, and one more abbreviation is not worth the outage.

Class colouring, message routing and channel membership are all left to the
client. Nothing here is rewritten except the URLs in it.

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
