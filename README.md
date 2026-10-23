# Drive Radio for Mac

A menu bar radio and a desktop / Notification Centre widget for the Drive Launcher station list
(the same stations as the car launcher, from `POST https://drivelauncher.teachmeit.lk/api/v1/radio`).

- **Menu bar app** (`App/`): plays the stations with AVPlayer, which handles the MP3, AAC and Shoutcast streams.
  - Shows the song when the station sends one.
  - Language filter, search, favourites (★), volume, and "Open at login".
  - Media keys and Control Center's Now Playing work.
  - Refreshes the list every 6 hours. The list in `Shared/stations.json` is used until the first fetch.
- **Widget** (`Widget/`): small (now playing + play/stop, previous, next); medium (+ 6 stations); large (+ 12 stations).
  - Favourites come first, then recently played stations.
- A widget can't play sound itself. Its buttons are App Intents (`Shared/RadioIntents.swift`) that hand the command
  to the app through the app group's defaults and a Darwin notification. If the app isn't running, the widget
  starts it, and the app runs the command at launch.

## Build and install
```
./build.sh
```
Needs Xcode and `xcodegen` (`brew install xcodegen`). It is signed with the Apple Development certificate of team
DH7LNR88KT; the app group is `DH7LNR88KT.lk.semicolon.driveradio`. It installs to `/Applications/Drive Radio.app`
and starts the app.

Then add the widget: right-click the desktop → **Edit Widgets** → search "Drive Radio" → pick a size.

## Station rules
Same as the launcher (see `/radio` on the website): names only, no logos; played straight from each station's own
server; the list is managed in Admin → Radio.
