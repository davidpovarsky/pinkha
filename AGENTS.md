# Repository agent instructions

## iOS CI runners

- Do not trigger, wait for, or use the `Swift tests (self-hosted, Xcode 27)` job as a validation gate. The self-hosted runner is persistently unavailable/hanging.
- An ordinary PR may enqueue that job automatically; ignore its queued/in-progress state and do not rerun it.
- Run Swift/iOS and real simulator validation through `.github/workflows/torah-ci.yml` on the GitHub-hosted `xcode-27` runner. Use its `workflow_dispatch` `full_suite=true` mode when the complete unit, integration, and XCUITest matrix is required.
- Use `.github/workflows/build-ipa.yml` on the GitHub-hosted `xcode-27` runner for unsigned IPA artifacts.
