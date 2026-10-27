# Contributing

Thanks for taking the time to improve Kubernetes Status! Bug reports, ideas and pull requests are all welcome.

## Getting started

You need macOS 14+ and a Swift 5.9+ toolchain (Xcode or the Command Line Tools).

```bash
git clone https://github.com/recepysl/kubernetes-status.git
cd kubernetes-status
make run          # build KubernetesStatus.app and launch it from the repo
```

To see the real pipeline without the UI, run `make once` (or `swift run KubernetesStatus --once --kubeconfig <file or folder>`).

## Before you open a pull request

- `make selftest` passes (and `make test` if you have Xcode).
- `swift build -c release` builds without warnings.
- If you changed anything visible, run `make screenshots` and commit the updated images in `docs/images/`.
- User-facing changes have an entry under an *Unreleased* heading in [CHANGELOG.md](CHANGELOG.md).

## Guidelines

- **Read-only.** The app may only run read operations (`get`, `logs`, `describe`, `config view`); it must never change a cluster or a kubeconfig.
- **Keep it dependency-free.** Apple frameworks only.
- **Keep logic in `KubeStatusKit`.** Anything that doesn't need SwiftUI belongs there, with assertions in `SelfCheck.swift`.
- **Be lenient with clusters.** Every field of a pod is optional in practice; unknown states must degrade to a sensible reason, never a crash.

## Commit messages

The history follows [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(app): show rollout status for deployments
fix(kit): treat CreateContainerError as critical
docs: explain namespace filters
```

Common types are `feat`, `fix`, `docs`, `test`, `build`, `ci`, `refactor` and `chore`. Scopes are `kit`, `app` and `cli`.

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Move the *Unreleased* changelog entries under the new version.
3. Tag and push: `git tag v1.3.0 && git push origin v1.3.0`.

The release workflow builds the DMG and publishes the GitHub release with the changelog section as notes.
