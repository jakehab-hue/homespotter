# HomeSpotter AR (native iOS)

Point your iPhone down a street and see a tag pinned above every house — address,
price estimate, and one-tap Zillow/Redfin links. Uses ARKit **geo tracking**:
Apple localizes the phone by matching the camera feed against its own street
imagery, so tags are accurate to roughly a degree instead of the 10–20° a
compass gives.

## Requirements

- Xcode (Mac App Store)
- iPhone with A12 chip or newer (iPhone XS / XR or later), iOS 16+
- An area covered by Apple geo tracking (most US metro areas)

## Build & install (first time)

```bash
brew install xcodegen        # already installed if Claude set this up
cd "ios"
xcodegen generate            # creates HomeSpotterAR.xcodeproj
open HomeSpotterAR.xcodeproj
```

In Xcode:
1. Click the **HomeSpotterAR** project → **Signing & Capabilities** → set
   **Team** to your personal team (sign in with your Apple ID if prompted).
2. Plug in your iPhone (unlock it, tap "Trust This Computer").
3. Pick your phone in the device dropdown at the top, press **⌘R**.
4. First run only: on the phone go to Settings → General → VPN & Device
   Management → trust your developer certificate.

Apps signed with a free Apple ID expire after 7 days — just press ⌘R again to
reinstall.

## Using it

- Walk outside and pan the phone at buildings across the street. The status pill
  says "localizing" until ARKit matches the scene, then "locked on".
- Tap a tag for the detail card with Zillow/Redfin/Google links.
- Gear icon → paste a RentCast API key (free at rentcast.io) to see price
  estimates above each house.
