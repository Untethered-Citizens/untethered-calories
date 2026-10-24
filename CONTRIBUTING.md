# Contributing to Untethered Calories

Thanks for your interest. This is a small project with one maintainer, so the process is kept simple and predictable. Please read this page before opening an issue or a pull request.

## How a change gets in

1. **Open an issue first.** Describe the bug or the idea. Every pull request must link an issue that the maintainer has agreed to, including what "done" looks like. Pull requests without an agreed issue are closed, however good the code is, so your time isn't wasted on something that won't be merged.
2. **Fork the repo and make a branch** from an up-to-date `main`, named `<type>/<issue>-<short-slug>`:
   - `fix/` for a bug, `feature/` for an enhancement, `docs/` for documentation, `chore/` for tooling and cleanup
   - Example: `fix/20-trend-text-cutoff`
   - One issue per branch. Unrelated changes belong in their own issue.
3. **Make small commits** with imperative messages ("Add weight unit setting").
4. **Before opening the pull request:** the app builds, all tests pass, new logic has tests, and UI changes have been checked in the simulator (light and dark mode where it matters).
5. **Open the pull request** and fill in the template. Put `Closes #N` on its own line.
6. **CI.** GitHub Actions builds the app and runs the tests on every pull request, and shows the result on it. It must be green (✅) before merging.
7. **Review.** The maintainer reviews every pull request and may ask for changes. Only the maintainer merges, using squash merge.

First-time contributors: GitHub waits for the maintainer to approve before running CI on your first pull request. That's normal.

## Building and testing

You need a Mac with the latest Xcode. No API key is needed to build or run the tests.

```bash
xcodebuild -project CalorieTracker.xcodeproj -scheme CalorieTracker -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project CalorieTracker.xcodeproj -scheme CalorieTracker -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Tests use Swift Testing (`import Testing`) with in-memory SwiftData. Add `-parallel-testing-enabled NO` if a run hangs. To try logging in the simulator, add your own Anthropic API key in the app's Settings.

The project uses folder-synced groups: a new `.swift` file in an existing folder is picked up without editing the project file. File names must be unique across the target.

## The rules that keep the numbers honest

Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing logging, storage or the dashboard. In short:

- Dates are **local calendar dates**, never UTC timestamps.
- Every write goes through `EntryWriter`, which runs the **macro integrity check** (`4P + 4C + 9F` within 15% of calories; alcohol is exempt).
- Every entry is exactly one of **Label**, **Estimate** or **Photo Estimate**, and an estimate is never promoted to a label.
- **Claude is only for parsing, estimating and conversation.** All arithmetic, totals, averages and charts are plain Swift.
- Gaps are gaps: never average over missing days, and leave today out of averages.

Pull requests that touch these areas must say so in the template.

## Out of scope

The app has no accounts, servers, analytics, ads, tracking or subscriptions, and talks only to Anthropic with the user's own key. Changes that add any of these won't be accepted. Adding our own encryption (beyond HTTPS, the Keychain and iOS file protection) also needs a discussion first, because it changes the app's export compliance declaration.

## Security

Never commit an API key, even a revoked one. If your change touches network calls, the Keychain or API-key handling, tick the security box in the pull request template so it gets a closer review.

To report a vulnerability, don't open an issue. See [SECURITY.md](SECURITY.md).

## Licence

The code is under the [Apache License 2.0](LICENSE). By opening a pull request, you agree that your contribution is licensed under the same terms (section 5 of the licence), and that you have the right to submit it.

The licence covers the code only. The name "Untethered Calories", the app icon and the Untethered Citizens branding aren't licensed for reuse (section 6). If you publish your own version, please give it a different name and icon.

## Conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
