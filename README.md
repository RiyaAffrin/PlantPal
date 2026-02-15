# PlantPal Prototype

PlantPal is an iOS prototype for plant-care guidance. It includes:
- A daily care view and reminder flow
- AI chat and care-plan generation via Gemini API
- Optional Google Sign-In + Google Calendar event creation

## Project Structure

- Xcode project: `PlantPal/PlantPal.xcodeproj`
- App source: `PlantPal/PlantPal/`
- Local secrets template: `PlantPal/PlantPal/Config/Secrets.xcconfig.example`

## Requirements

- macOS with Xcode (recommended: Xcode 16+)
- iOS Simulator (iOS 17.0+)
- Internet connection for Gemini / Google Calendar features
- Apple Developer signing setup in Xcode (for running on a real device)

## Configuration (API Keys / OAuth)

This prototype reads runtime keys from `Secrets.xcconfig`.

1. Create a local config file:

```bash
cp PlantPal/PlantPal/Config/Secrets.xcconfig.example PlantPal/PlantPal/Config/Secrets.xcconfig
```

2. Copy `PlantPal/PlantPal/Config/Secrets.xcconfig.example` and edit the file:

```xcconfig
GEMINI_API_KEY = YOUR_API_KEY_HERE
GOOGLE_CLIENT_ID = YOUR_GOOGLE_OAUTH_CLIENT_ID
GOOGLE_REVERSED_CLIENT_ID = YOUR_REVERSED_GOOGLE_CLIENT_ID
```

### If you omit API keys

You may omit `GEMINI_API_KEY` when submitting the prototype. If omitted:
- The app still builds and launches.
- Gemini-powered chat/care-plan actions will fail at runtime with a missing-key message.

You may also omit Google OAuth credentials. If omitted:
- Non-Google features still run.
- Google Sign-In / Calendar sync will not work.

## Build and Run in Xcode

1. Open `PlantPal/PlantPal.xcodeproj` in Xcode.
2. Select scheme `PlantPal`.
3. Choose an iOS Simulator target (for example, iPhone 16).
4. Click **Run** (`Cmd + R`).

Xcode will automatically resolve the Swift Package dependency (`GoogleSignIn`).

## Build from Terminal (Optional)

From repository root:

```bash
cd PlantPal
xcodebuild -project PlantPal.xcodeproj -scheme PlantPal -destination 'platform=iOS Simulator,name=iPhone 16' build
```

If the simulator name is different on your machine, list available destinations with:

```bash
xcodebuild -project PlantPal.xcodeproj -scheme PlantPal -showdestinations
```

## Notes

- Deployment target is iOS 17.0.
- Secrets should stay local and should not be committed to version control.
