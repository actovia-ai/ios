# Contributing to Actovia for iOS

Hi! We are really excited that you are interested in contributing to Actovia. Before submitting your contribution, please take a moment to read through the following guide.

## Repo Setup

The iOS app ([actovia-ai/ios](https://github.com/actovia-ai/ios)) is a SwiftUI app generated with [Tuist](https://tuist.dev); it talks to the Actovia desktop app it is paired with.

```bash
tuist install
tuist generate --no-open   # creates ActoviaIos.xcworkspace
xcodebuild test -workspace ActoviaIos.xcworkspace -scheme NetworkingKit -destination "platform=iOS Simulator,name=iPhone 17"
python3 scripts/l10n.py audit   # every user-facing string, in every language
```

## Pull Request Guidelines

- Checkout a topic branch from `main` and merge back against it.

- If adding a new feature:
  - Add accompanying tests.
  - Provide a convincing reason to add this feature. Ideally, open a suggestion issue first and have it approved before working on it.

- If fixing a bug:
  - If you are resolving a special issue, add `(fix #xxxx[,#xxxx])` (#xxxx is the issue id) in your PR title for a better release log, e.g. `fix: keep the paired computer after a restart (fix #12)`.
  - Provide a detailed description of the bug in the PR.
  - Add appropriate test coverage if applicable.

- It's OK to have multiple small commits as you work on the PR — GitHub can squash them before merging.

- Make sure the checks above pass.

- Commit messages follow the [Angular Team's Commit Message Guidelines](https://github.com/angular/angular/blob/master/CONTRIBUTING.md#commit): releases and the changelog are generated from them.

- Every user-facing string is a key in `Resources/App/Localizable.xcstrings` with all languages filled (`scripts/l10n.py`); see the README.

## Reporting Security Issues

Please do not open an issue for a security problem; see [SECURITY.md](SECURITY.md).
