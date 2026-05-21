# Migration Guide: erlmcp 0.5.x to 0.6.0

> **Status:** Stub. This document is filled in as the `erlmcp` public facade
> solidifies during M2+. Breaking changes are listed as they are implemented.

## Overview

erlmcp 0.6.0 is an intentional clean break from 0.5.x. The public API surface
is the `erlmcp` module — all other modules are internal and may change without
notice between minor versions.

## API Mapping

| 0.5.x entry point | 0.6.0 equivalent | Notes |
|--------------------|-------------------|-------|
| `erlmcp_server:start_link/2` | TBD | |
| `erlmcp_server:add_tool/3` | `erlmcp:add_tool/2` (planned) | Schema via `erlmcp_schema` builder |
| `erlmcp_client:start_link/2` | TBD | |
| `erlmcp_client:initialize/3` | TBD | |
| `erlmcp_stdio_server:start_link/1` | TBD | Subsumed by session model |

## Removed Modules

| Module | Reason | Replacement |
|--------|--------|-------------|
| `erlmcp_server_new` | Parallel fork eliminated (M0) | `erlmcp_server_session` |
| `erlmcp_transport_stdio_new` | Parallel fork eliminated (M0) | `erlmcp_transport_stdio` |

## New Architecture

See `docs/0.6.0/planning/phase2-idiomatic-erlmcp.md` for the full design.
Key changes:

- Server and client sessions are `gen_statem` state machines
- One process per in-flight request (cancellation = process exit)
- Transport is a behaviour with pid-based ownership
- JSON access isolated behind `erlmcp_codec`
- Registry is discovery-only (off the message hot path)
