# Calorie Tracker (working name)

A conversational calorie and macro tracker for iPhone. Tell it, or show it a photo of, what you ate, and Claude turns that into logged entries using **your own Anthropic API key**.

- All data stays on your device.
- No accounts, ads, subscriptions or tracking.
- Every entry is honestly labelled as coming from a label or an estimate.

> Status: early development. Not yet usable.

## How it works (planned)
- **Logging:** chat or photo. Numbers you give (or a nutrition label) are logged immediately. Estimates are shown as a card for one-tap confirmation.
- **Dashboard:** Today, Week, Weight (from Apple Health) and an intake-vs-weight Trend.
- **Bring your own AI:** paste your own AI key (an Anthropic API key) once. It's stored in the iOS Keychain, and requests go straight from your phone to Anthropic.

## Building
Requires Xcode (latest) on macOS. Build instructions will be added once the Xcode project exists.

## Credits

The app uses the [Barlow](https://github.com/jpt/barlow) and Barlow Condensed typefaces by The Barlow Project Authors, under the SIL Open Font License 1.1 (`CalorieTracker/Resources/Fonts/OFL.txt`).
