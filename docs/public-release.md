# Public release checklist

This checklist covers publishing the repository and preparing a development installation. It does not certify a production service or an App Store release.

## Owner decisions before changing visibility

- [x] The owner selected the [MIT License](../LICENSE) on 2026-11-06. Third-party licenses and notices remain in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
- [x] The owner chose to retain the existing Git history on 2026-11-06, including the previously reviewed personal author/committer email metadata. No history rewrite or clean-history copy is planned.
- [ ] Review the branches, pull requests, issues, workflow logs/artifacts, images, and other material that will become visible. Confirm rights to distribute code and assets, including any later additions.
- [ ] Decide whether the initial publication is source only or includes installable artifacts. Keep the experimental status and supported setup clear.
- [ ] Confirm the final commit and repository visibility change explicitly. Merging a preparation branch alone does not publish the repository.

## Review evidence from 2026-11-06

The preparation review began at master commit `54a06391635d729a77292895c52a74f698fef51b`. The inspected history comprised five original branches, 52 reachable commits, 49 distinct trees, and 260 distinct text blobs. A checksum-verified Gitleaks 8.30.1 scan covered historical text, commit/discussion metadata, five complete Actions logs, and the working tree. It reported no credential findings in that inspected material.

This is a bounded review, not a guarantee. It does not prove that every external artifact, deleted/unreachable object, private deployment, or provider account is free of sensitive information. The owner chose to retain the reviewed history and its email metadata on 2026-11-06. Nonsecret historical deployment identifiers are not, by themselves, evidence of a credential leak.

## Source publication checks

- [ ] Run `npm ci --prefix floating` and `python3 scripts/check.py` from a clean checkout.
- [ ] Require the preparation PR's CI to pass, including Python/config checks, SAM validation, TypeScript checks/tests, dependency audit, secret scan, and iOS tests. Local Linux checks cannot substitute for the Xcode job.
- [ ] Review outstanding dependency advisories, including any below the CI failure threshold. Passing `npm audit --audit-level=high` does not mean there are no advisories.

At the preparation review, npm reported no high or critical advisories and 14 moderate affected package nodes tracing to one underlying [OpenTelemetry advisory, GHSA-8988-4f7v-96qf](https://github.com/open-telemetry/opentelemetry-js/security/advisories/GHSA-8988-4f7v-96qf). The compatible lockfile update removed the high-severity findings. The remaining dependency chain needs a reviewed upstream update; the automated force-fix suggested a breaking SDK downgrade, which was not applied. Recheck the final lockfile before publication; this snapshot is not a continuing guarantee.

## Additional checks before distributing or deploying the app

These checks concern runnable installations and release artifacts. They are not prerequisites for publishing the source with its experimental status and limitations documented.

- [ ] Build the iOS app and both extensions with your own signing configuration. Verify all bundle IDs, all three entitlements, and shared App Group identifiers are consistent.
- [ ] Smoke-test sign-in, Reminders permission, sync, capture, widget refresh, completion, archive/restore, and sign-out using synthetic data in a development deployment. Background refresh must be tested on a device.
- [ ] If enabling Photon, verify the webhook's signature and sender checks separately from the companion's iMessage-only, direct-conversation reply policy. The webhook does not filter conversation type or direction. Use synthetic input to verify rejection paths before using real task content.
- [ ] If deploying a Pi, supply temporary credentials, verify read-only access to the intended user partition, and test offline fallback on the actual device. The repository does not contain a complete device installer/display application.

## Configure the public project and deployment

- [ ] Enable private vulnerability reporting, choose maintainer notification settings, and ensure the route described in [SECURITY.md](../SECURITY.md) is usable.
- [ ] Configure branch protection or the repository rules available on the account, with CI review requirements appropriate to the project.
- [ ] Set a concise repository description and topics. Publish only screenshots containing synthetic data.
- [ ] Decide retention/deletion behavior for DynamoDB, all S3 object versions, CloudWatch logs, messaging services, and device caches. The current template retains the archive bucket without an expiry policy.
- [ ] Document operating costs, account recovery, backups, and deletion before offering a hosted installation to other users. AWS resources incur charges; the repository makes no cost guarantee.

Keep real `.env` files, local Xcode configuration, deployment state, signing assets, credentials, and cached task data out of commits and release artifacts. Release preparation does not require messaging real contacts or changing live reminders.
