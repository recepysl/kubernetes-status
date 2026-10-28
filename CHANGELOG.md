# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-28

### Added
- **Rancher support.** Add a Rancher server URL and API token in Settings and every cluster the token can see becomes a context. Pods are listed through Rancher, so only namespaces you have access to are returned — no cluster-wide permission or namespace filters needed. The token is stored in the Keychain.
- Contexts in any kubeconfig that point at Rancher (`…/k8s/clusters/<id>` with a bearer token) are detected and fetched the same way.
- **Cluster details** for Rancher clusters: provider, Kubernetes version, node count, cluster state, and CPU / memory / pod requests against allocatable capacity.
- Healthy contexts show how many namespaces their pods span.
- `--once` prints cluster details under each context.
- `scripts/install.sh` one-line installer that downloads the latest release into `/Applications` without the quarantine flag.

### Changed
- Install instructions cover the macOS 15+ *“could not verify”* dialog (**Open Anyway** in Privacy & Security).

## [1.0.0] - 2026-10-27

First release.

### Added
- Menu bar icon colored by the worst pod across all watched contexts, with a count of unhealthy pods.
- Dropdown listing every watched context with ready/total counts; contexts with problems expand to show failing pods with namespace, readiness, restarts, age and reason.
- One-click **logs** (follow) and **describe** in Terminal, plus copy actions.
- Pod classification for crash loops, image pull failures, OOM kills, configuration errors, stuck `Pending` / `NotReady` pods (after a 5-minute grace period), failed Jobs and evictions.
- Kubeconfig files and folders, per-context namespace filters, automatic fallback to the context namespace when cluster-wide listing is forbidden.
- Notifications when a pod starts failing.
- Settings window: kubeconfig paths, `kubectl` path, watched contexts, refresh interval, notifications, *Open at Login*.
- CLI modes: `--once`, `--selftest`, `--render-screenshots`.

[1.1.0]: https://github.com/recepysl/kubernetes-status/releases/tag/v1.1.0
[1.0.0]: https://github.com/recepysl/kubernetes-status/releases/tag/v1.0.0
