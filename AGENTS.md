# Repository agent instructions

## iOS CI runners

- Do not trigger, wait for, or use the `Swift tests (self-hosted, Xcode 27)` job as a validation gate. The self-hosted runner is persistently unavailable/hanging.
- An ordinary PR may enqueue that job automatically; ignore its queued/in-progress state and do not rerun it.
- Run Swift/iOS and real simulator validation through `.github/workflows/torah-ci.yml` on the GitHub-hosted `xcode-27` runner.
- Default to the smallest focused test selection that covers the files and behavior changed. Do not rerun the complete unit, integration, and XCUITest matrix after each fix.
- Run the complete matrix with `workflow_dispatch` `full_suite=true` only when the user's current request explicitly asks for a full run. A full run requested earlier does not authorize repeating it after subsequent fixes unless the user asks again.
- After a failed focused run, fix the failure and rerun only the affected package, test target, test class, or test case whenever the workflow permits it.
- Use `.github/workflows/build-ipa.yml` on the GitHub-hosted `xcode-27` runner for unsigned IPA artifacts.
