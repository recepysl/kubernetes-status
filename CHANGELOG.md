# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

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

[1.0.0]: https://github.com/recepysl/kubernetes-status/releases/tag/v1.0.0
