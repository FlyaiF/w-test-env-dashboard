# Move from a local desktop tool to a client-server system with a single central backend

> Status: accepted

The dashboard must be usable by all of dev/QA with **shared** data, which the old per-desktop model
(each app spawns its own Go sidecar, holds its own local JSON cache, no sharing) cannot provide. We
are introducing a single central backend that owns the canonical data, runs Collection, and serves
thin clients; the desktop app becomes a thin client. The network across the test environment is open,
so a single backend can reach every Database/Server — we explicitly reject splitting out separate
collector agents (ADR scope: do that only if network segmentation later forces it). The cost we
accept is that there is now a service to deploy and operate, which did not exist before.
