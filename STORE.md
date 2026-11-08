# Publishing on the App Store

What's ready in this repo, and what's left to do in App Store Connect.

## Ready

* **Privacy manifest:** `App/Resources/PrivacyInfo.xcprivacy`, which Apple asks of every app: no tracking, no data collected, and `UserDefaults` declared for the app's own settings (reason CA92.1)
* **The app's name and location prompt in both languages:** `App/Resources/el.lproj` and `en.lproj` (`InfoPlist.strings`), so the permission prompt is in the phone's language
* **Export compliance:** `ITSAppUsesNonExemptEncryption` is false in `project.yml` (the app only uses HTTPS)
* **Icon** (1024 x 1024, no transparency), launch screen, and a build number that goes up with every release
* **Store listing,** in Greek (`el`) and English (`en-US`), in `fastlane/metadata/<locale>/`: name, subtitle, description, keywords, promotional text, and the support, privacy and marketing URLs. Category: Navigation, then Travel
* **Screenshots** for the 6.9" display (1320 x 2868) in `fastlane/screenshots/<locale>/`, made by `scripts/store_assets.py` from the Screenshots workflow's full-size images
* **Privacy policy:** https://kastoria-dev-core.github.io/privacy/ · **Support:** https://kastoria-dev-core.github.io/support/

The folder layout is fastlane's, so `fastlane deliver` can upload the listing and the screenshots from CI.

## Left to do

1. **The account.** An Apple Developer Program membership (99 USD a year). As an organisation, e.g. Astiko KTEL Kastorias, it needs a D-U-N-S number and the publisher shown on the App Store is the organisation; as an individual, it's that person's name
2. **The operator's say-so.** The app is named after the operator and says it's their official app, so Apple wants it published from the operator's account or with their written authorisation (App Review guideline 5.2)
3. **The app in App Store Connect,** with the bundle id `com.kastoriadevs.astikoktel` registered in the developer account
4. **Signing and uploading from CI.** With the account, add these repository secrets, and `release.yml` gets an archive, sign and upload step to TestFlight in place of the unsigned `.ipa`. It runs on GitHub's macOS runners like now:
   * `APPLE_TEAM_ID`
   * `IOS_DIST_CERT_P12_BASE64` and `IOS_DIST_CERT_PASSWORD`: the Apple Distribution certificate
   * `APPSTORE_API_KEY_ID`, `APPSTORE_API_ISSUER_ID`, `APPSTORE_API_KEY_P8_BASE64`: an App Store Connect API key with the App Manager role
5. **TestFlight** on real iPhones, then **submit for review** with the answers below

## Answers for App Store Connect

**App Privacy:** Data Not Collected.

* Location is used only on the device, when the user asks for stops near them, and is never sent off it, so under Apple's definitions it isn't collected
* No accounts, analytics, ads, tracking or crash reporting

**Age rating:** no objectionable content of any kind, no unrestricted web access, no gambling, no user-generated content. It comes out as 4+.

**App Review notes:**

> No sign-in needed. Location is optional and only used on the device to find nearby stops; the app works fully without it. Live bus positions appear only while buses are running (roughly 07:00 to 22:00 Greek time); outside those hours the app shows timetable times.

**Pricing:** free, no in-app purchases.

**Devices:** iPhone only, iOS 17 or newer. On an iPad it runs in iPhone compatibility mode.
