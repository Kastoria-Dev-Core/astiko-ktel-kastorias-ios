<div align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="100" />
  <h1>Kastoria City Buses for iOS</h1>
  <p>Every city bus line, stop and timetable in Kastoria, on your iPhone.</p>
</div>

The iPhone version of [astiko-ktel-kastorias-app](https://github.com/Kastoria-Dev-Core/astiko-ktel-kastorias-app). It's written in SwiftUI and does the same things the same way:

* The same data: the network the Android repo publishes (`transit.json`), downloaded at start so a timetable change reaches the app without a new release, with a copy built in for offline use
* The same live buses, from the drivers' phones through [astiko-ktel-live](https://github.com/Kastoria-Dev-Core/astiko-ktel-live)
* The same announcements, from astiko-ktel-announcements
* The same text in Greek and English, brought over from the Android `strings.xml`
* The same rules: the timetable logic, holidays and Orthodox Easter, the journey planner, the bus estimates and the live times are ports of the Kotlin code, with the same tests

## Features

* Next departures for any stop, with live times (the signal icon) for buses whose phone is sending
* Favourite stops on Home, search in Greek, English or Greeklish, with or without accents
* "Where do you want to go?": the buses from the stops near you to the centre, Maniakoi or the university
* Every line with its full timetable, the operator's notes, and where its buses are along the route
* A map of every stop with Apple Maps, a filter per line with its route along the streets, the buses, and a card with the next departures when you tap a stop
* Voice announcements of a stop's next buses
* The operator's announcements with their posters
* Greek and English, light and dark, chosen in Settings

## Installing it without an Apple developer account

Releases are unsigned `.ipa` files:

https://github.com/Kastoria-Dev-Core/astiko-ktel-kastorias-ios/releases

To put one on an iPhone from Windows, use [Sideloadly](https://sideloadly.io/) (or AltStore). It signs the app with a free Apple ID as it installs it. Apple lets such an install run for 7 days, after which you install it again. It needs iOS 17 or newer.

Every pull request also builds one, under the run's Artifacts ("ipa").

## Building it

No one on the team has a Mac, so CI is where the app is built (`.github/workflows/build.yml`, on a macOS runner):

1. [XcodeGen](https://github.com/yonaskolb/XcodeGen) makes `AstikaKastorias.xcodeproj` from `project.yml`. The project file isn't committed: `project.yml` is the project
2. The tests run on the iPhone simulator
3. `scripts/screenshots.sh` opens the main screens on the simulator in Greek and English, light and dark, and keeps the screenshots (Artifacts, "screenshots"). That's how a change is seen without a Mac
4. An unsigned app for real iPhones is built and kept (Artifacts, "ipa")

On a Mac:

```bash
brew install xcodegen
xcodegen
open AstikaKastorias.xcodeproj
```

## Releasing

Like the Android app: bump `MARKETING_VERSION` in `project.yml` and merge. `.github/workflows/release.yml` publishes release `v<version>` with the `.ipa`, only when the version goes up.

## When there's a developer account

The App Store and TestFlight need an Apple Developer Program membership (99 USD a year). With one:

* Set `DEVELOPMENT_TEAM` in `project.yml`
* Add the signing certificate and an App Store Connect API key as repository secrets, and have `release.yml` archive, sign and upload to TestFlight instead of making an unsigned `.ipa`. That still runs on GitHub's macOS runners, so it doesn't need a Mac either
* The bundle id is `com.kastoriadevs.astikoktel`

The App Store adds terms the GPL doesn't allow on its own, so `NOTICE` has an extra permission from the authors for the App Store and TestFlight.

## How the code is laid out

```
project.yml              the Xcode project, for XcodeGen
App/
  Resources/
    transit.json         the whole network, the same file the Android repo publishes
    strings.json         Greek and English text, made by scripts/import_strings.py
    Fonts/               Commissioner, as in the Android app
    Assets.xcassets      the icon, the app mark and the colours
  Sources/
    App/                 the app entry, the shared container, the strings
    Data/                models, the network, live buses, announcements, settings, location
    Domain/              timetable logic, bus estimates, live trips, journey planner, search
    UI/                  the screens and the pieces they share
Tests/                   the timetable logic and checks against the bundled network
scripts/
  import_strings.py      brings the text over from the Android app
  screenshots.sh         the screenshots CI takes
```

To bring new text over after the Android app changes its strings:

```bash
python scripts/import_strings.py
```

## License

[GNU General Public License v3.0](LICENSE) or later, like the Android app. See [NOTICE](NOTICE).
