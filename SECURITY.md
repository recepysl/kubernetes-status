# Security Policy

Kubernetes Status works with cluster credentials, so it is designed to touch as little as possible.

## What the app accesses

| Resource | Access | Why |
| --- | --- | --- |
| Kubeconfig files and folders you configure | Read, by `kubectl` | Contexts, servers and credentials |
| `kubectl` and its exec credential plugins | Run | Every cluster request goes through your own `kubectl` |
| Your clusters | Read only: `get pods`, plus `logs` / `describe` in Terminal when you click them | Pod health |
| `UserDefaults` | Read / write | Settings (paths, watched contexts, namespace filters, interval) |
| Notification Center | Post | Local alerts when a pod starts failing, if enabled |

The app never parses, stores or transmits credentials itself, never writes to a kubeconfig, never runs a command that modifies a cluster, and sends no data anywhere else. There is no analytics or telemetry.

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Instead, use GitHub's [private vulnerability reporting](https://github.com/recepysl/kubernetes-status/security/advisories/new) for this repository. You can expect an initial response within a few days.
