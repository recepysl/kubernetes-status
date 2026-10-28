# Security Policy

Kubernetes Status works with cluster credentials, so it is designed to touch as little as possible.

## What the app accesses

| Resource | Access | Why |
| --- | --- | --- |
| Kubeconfig files and folders you configure | Read, by `kubectl` | Contexts, servers and credentials |
| `kubectl` and its exec credential plugins | Run | Every cluster request goes through your own `kubectl` |
| Your clusters | Read only: `get pods`, plus `logs` / `describe` in Terminal when you click them | Pod health |
| Rancher API (only for servers you add, or Rancher contexts in your kubeconfig) | Read only: `GET /v3/clusters`, `GET /k8s/clusters/<id>/v1/pods` | Cluster list, capacity and pods |
| Keychain | Read / write its own item | The Rancher API tokens you add in Settings |
| `~/Library/Application Support/<bundle id>/rancher/` | Write | Generated kubeconfig for added Rancher servers (`0600`), so `kubectl` can run *Logs* / *Describe* |
| `UserDefaults` | Read / write | Settings (paths, watched contexts, namespace filters, interval, Rancher server URLs) |
| Notification Center | Post | Local alerts when a pod starts failing, if enabled |

Apart from Rancher API tokens you add yourself (kept in the Keychain and in the generated, owner-only kubeconfig above) and the bearer token of a Rancher context, which is sent only to that context's own Rancher server, the app never stores or transmits credentials, never writes to your kubeconfig files, never runs a command that modifies a cluster, and sends no data anywhere else. There is no analytics or telemetry.

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Instead, use GitHub's [private vulnerability reporting](https://github.com/recepysl/kubernetes-status/security/advisories/new) for this repository. You can expect an initial response within a few days.
