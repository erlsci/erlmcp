# erlmcp

[![Build Status][gh-actions-badge]][gh-actions]
[![Coverage][coverage-badge]][project]
[![][tag-badge]][tag]

[![Project Logo][logo]][logo-large]

*Erlang/OTP implementation of the Model Context Protocol (MCP).*

## What It Is

erlmcp is an Erlang/OTP implementation of the
[Model Context Protocol](https://modelcontextprotocol.io/) (MCP 2025-11-25).
It provides both server and client sessions, built on `gen_statem` with
per-request process isolation, cancellation-as-exit, and transport-agnostic
design.

## Status

**0.6.0** — complete re-core. Production-grade server and client with:

- Full MCP 2025-11-25 protocol surface (tools, resources, prompts, logging,
  completion, sampling, roots, elicitation)
- Conformance scorecard: server 100%, client 100%, transport 100%
- Test coverage: 93% aggregate, every module ≥90%
- 527 tests (409 EUnit + 110 CT + 8 PropEr)

## Install

Add to your `rebar.config`:

```erlang
{deps, [
    {erlmcp, {git, "https://github.com/erlsci/erlmcp.git", {tag, "0.6.0"}}}
]}.
```

## Quickstart

```erlang
%% Start a server session
{ok, Server} = erlmcp:start_server(my_server),

%% Register a tool
Schema = erlmcp_schema:object([
    erlmcp_schema:field(<<"city">>, erlmcp_schema:string(), [required])
]),
ok = erlmcp:add_tool(Server, #{
    name => <<"get_weather">>,
    description => <<"Look up weather for a city">>,
    input_schema => Schema,
    handler => fun(#{<<"city">> := City}, _Ctx) ->
        {ok, erlmcp:text(<<"Sunny in ", City/binary>>)}
    end
}),

%% Or use a handler behaviour module
ok = erlmcp:register_handler(Server, my_tools).
```

See the [examples](test/) for complete calculator, weather, client, and
sampling examples with CT suites.

## Documentation

- [Architecture](docs/architecture.md) — session lifecycle, workers, transports
- [Protocol](docs/protocol.md) — MCP 2025-11-25 method coverage
- [OTP Patterns](docs/otp-patterns.md) — let-it-crash, supervision, validation
- [API Reference](docs/api-reference.md) — all exports
- [Migration Guide](docs/0.6.0/MIGRATION-0.5-to-0.6.md) — porting from 0.5

## Versioning

erlmcp follows [Semantic Versioning](https://semver.org/). The 0.6.0 release
is a breaking re-core — see the migration guide for details. Release notes
are maintained in Git tags.

## License

Apache 2.0

## External Resources

- [Model Context Protocol](https://modelcontextprotocol.io/introduction)
- [Conformance Scorecard](conformance/results/)

[//]: ---Named-Links---

[project]: https://github.com/erlsci/erlmcp
[logo]: priv/images/logo.png
[logo-large]: priv/images/logo-large.png
[gh-actions-badge]: https://github.com/erlsci/erlmcp/workflows/ci/badge.svg
[gh-actions]: https://github.com/erlsci/erlmcp/actions?query=workflow%3Aci
[coverage-badge]: https://img.shields.io/badge/coverage-93%25-brightgreen
[tag-badge]: https://img.shields.io/github/tag/erlsci/erlmcp.svg
[tag]: https://github.com/erlsci/erlmcp/tags
