# Sprout

Mentor and new-player matchmaking for **WoW Forever**. Flag a character as a
**Sprout** (new or returning, looking for help) or a **Mentor** (experienced,
offering help), see who else on your realm cluster has done the same, and
whisper or invite them from a roster window.

## Usage

| Command | Effect |
| --- | --- |
| `/sprout` | Toggle the roster window |
| `/sprout role off\|sprout\|mentor` | Set this character's role |
| `/sprout note <text>` | Set the note others see next to your name (max 80 chars) |
| `/sprout config` | Open the settings panel |
| `/sprout status` | Show channel and roster status |
| `/sprout debug` | Toggle protocol logging in the chat frame |

The roster window has two boxes, Sprouts and Mentors. Each row shows name,
level, class and zone, with Whisper, Invite and Note buttons. Hovering a name
shows the player's note and your own private note about them. Private notes
are account-wide; role and own note are per character.

Scope: discovery runs over a hidden custom chat channel, so it reaches your
connected-realm cluster and faction, not the whole game.

## How it works

- On login the addon silently joins a hidden custom channel
  (`JoinTemporaryChannel` with no chat frame) and retries until the channel
  list has populated. Join/leave notices for it are filtered from chat.
- Presence is exchanged with addon messages over that channel using a
  registered prefix. Messages are `version;TYPE;key=value;...` strings, so
  fields can be added later without breaking older clients.
- Every 2 minutes each active player broadcasts a heartbeat (`HB`) with role,
  level, class, zone and note. Opening the window sends `WHO`; active peers
  reply `HERE` after a 0-2 s random delay. `BYE` is sent when switching to Off
  and, best effort, on logout.
- Roster entries expire after 3 missed heartbeats. The roster is in memory
  only and rebuilt every session.
- Characters set to Off still join the channel and can browse, but never
  announce themselves or answer `WHO`.
- Sending goes through AceComm and ChatThrottleLib, which paces traffic and
  re-queues messages the client rejects with the addon-message throttle.

## Layout

```
Sprout.toc         addon manifest (Interface 16001 = WoW Forever)
embeds.xml         library load order
Constants.lua      tunables: channel name, intervals, limits, roles
Protocol.lua       wire format encode/decode (pure Lua, unit tested)
Roster.lua         in-memory roster (pure Lua, unit tested)
Core.lua           AceAddon object, AceDB saved variables, slash commands
Player.lua         live character info (name-realm, level, class, zone)
Channel.lua        hidden channel join/rejoin/health check
Comm.lua           heartbeat, WHO/HERE/BYE, roster expiry
Options.lua        AceConfig settings panel
UI/RosterWindow.lua  two-box AceGUI roster window
UI/NoteDialog.lua    private note editor
libs/              Ace3 (gitignored, see below)
tests/             pure-Lua tests: lua tests/run.lua
```

## Development setup

1. Fetch the embedded libraries (they are not committed; the packager pulls
   them at release time from `.pkgmeta`):

   ```sh
   ./scripts/fetch-libs.sh
   ```

2. Symlink the repo into the WoW Forever AddOns folder under the addon's
   name. The folder name must match the `.toc` name:

   ```sh
   ln -s "$(pwd)" "/Applications/World of Warcraft/_forever_/Interface/AddOns/Sprout"
   ```

   Adjust the `_forever_` segment to whatever the beta client uses.

3. In game, enable Lua errors and confirm the interface number:

   ```
   /console scriptErrors 1
   /run print(select(4, GetBuildInfo()))
   ```

   If the printed number differs from `## Interface:` in `Sprout.toc`,
   update it. BugSack + BugGrabber are recommended for readable errors.

4. Run the pure-Lua tests (needs a Lua interpreter, e.g. `brew install lua`):

   ```sh
   lua tests/run.lua
   ```

Two clients on the same connected realm are needed to test discovery
end-to-end. `/sprout debug` prints every message sent and received.

## Known beta quirks (not addon bugs)

- SavedVariables are sometimes written but not reloaded on a fresh client
  start. If role or notes vanish after a full relog, check whether other
  addons lose settings too before debugging Sprout.
- `WOW_PROJECT_ID` reports as Retail; the addon does not branch on it.

## Getting a build

Every push runs `.github/workflows/build.yml`, which packages the addon with
Ace3 included and attaches it as an artifact. On GitHub open the Actions tab,
pick the latest Build run, download `Sprout` under Artifacts, unzip it and
copy the `Sprout/` folder into `Interface/AddOns`. Artifacts are kept for
30 days.

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager)
via `.github/workflows/release.yml` when a `v*` tag is pushed. It pulls Ace3
from `.pkgmeta`, replaces `@project-version@` in the TOC, and uploads to
CurseForge and Wago when `CF_API_KEY` / `WAGO_API_TOKEN` secrets and the
`X-Curse-Project-ID` / `X-Wago-ID` TOC fields are set. `CHANGELOG.md` is
used as the release notes.
