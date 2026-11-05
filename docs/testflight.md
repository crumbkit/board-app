# TestFlight

The iPhone app can reach the phone through TestFlight, so the phone needs
neither a cable nor Developer Mode. The Mac app cannot: TestFlight on the Mac
requires the App Sandbox, which would stop it running `board` and `git`. It
stays a build `bin/install-mac` signs.

- `bin/testflight` archives the iPhone app with a build number from the
  time, and uploads it to App Store Connect. The owner runs it.
- Every build, signed for development or for the App Store, uses iCloud's
  Production environment, so a TestFlight phone and a locally signed Mac read
  the same records. `CLOUDKIT_ENVIRONMENT=Development` in the environment of
  `bin/install-mac` or `bin/install-phone` builds for Development instead.
- The iPad layout allows every orientation, as App Store Connect requires.
- `Apps/iOS/PrivacyInfo.xcprivacy` declares the app's use of `UserDefaults`,
  which App Store Connect requires.
- The app has an icon, which App Store Connect requires: the Icon Composer
  file `Apps/Shared/AppIcon.icon`. The build compiles it into the app's
  asset catalog with every size and look, including the 1024 px App Store
  image.

## Before the first upload

The owner does each of these once:

- Create the app in App Store Connect with bundle id `com.stemmacorp.board`.
- Deploy the container's schema from Development to Production in the
  CloudKit Dashboard. Production makes no record type on first use, so the
  types and fields must first exist in Development. With both apps built for
  Development, pair, approve one request, refuse one with a reason, reply to
  one, share a put that replaces an existing value, answer one question, and
  answer one again from the phone after it was answered elsewhere. The
  Dashboard should then list PairingRequest, PairingChallenge, PairingGrant,
  Request, Shared, Answer, Reply, Question, QuestionAnswer and
  QuestionRefused. Deploy again after a change adds a record type or field.
- Answer the export compliance question. App Store Connect asks it for every
  build until `ITSAppUsesNonExemptEncryption` is set in `project.yml`. The
  app signs with the Secure Enclave and checks signatures.

## Not built

- Nothing uploads from CI.
- No build has been uploaded.
