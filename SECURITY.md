# Security policy

## Reporting a vulnerability

Please **don't open a public issue** for a security problem.

Report it privately instead: on this repository, go to the **Security** tab and choose **Report a vulnerability**. Only the maintainer can see the report. Please include what you found, how to reproduce it, and which version of the app or commit it affects.

You'll get a reply as soon as practical. This is a one-person project, so allow a few days. Once a fix is released, the report can be published with credit to you, if you'd like.

## What's in scope

The app has no server and no accounts. The most sensitive things it handles are:

- the user's Anthropic API key, stored in the iOS Keychain
- the user's food log, stored on the device
- the requests sent from the phone to `api.anthropic.com`

Anything that could leak, misuse or expose these is in scope. Problems with Anthropic's own service should go to Anthropic.

## Supported versions

Only the latest release on the App Store, and `main`, receive fixes.
