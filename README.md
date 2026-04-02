# Ledgr

Ledgr is a [Phoenix](https://www.phoenixframework.org/) web application for running day-to-day business operations: storefronts, orders, inventory, accounting, and admin tooling. The codebase supports multiple business domains, each with its own PostgreSQL database and feature set.

## Tech stack

- **Elixir** (~> 1.15) and **Phoenix** (~> 1.8) with **LiveView**
- **Ecto** / **PostgreSQL** for persistence
- **Tailwind CSS** and **esbuild** for assets
- **Stripe** for payments where storefront checkout is enabled

## Prerequisites

- Elixir and Erlang/OTP (see `mix.exs` for the supported Elixir version)
- PostgreSQL
- Node is not required for routine development; asset tooling is managed via Mix tasks

## Getting started

Clone the repository, then from the project root:

```sh
mix setup
```

This fetches dependencies, creates and migrates the default development database (see `mix.exs` aliases), runs seeds for the primary dev repo, and builds front-end assets.

Start the development server:

```sh
mix phx.server
```

Then open the URL printed in the terminal (by default [http://localhost:4000](http://localhost:4000)).

## Configuration

- **Development** database credentials and repo layout live under `config/dev.exs` and `config/test.exs`.
- **Production** uses runtime configuration in `config/runtime.exs` (for example `DATABASE_URL` and optional URLs per tenant repo). Set only the env vars for the environments and tenants you actually run.

The application may start optional Ecto repos only when their corresponding database URL env vars are present, so local or partial deployments do not need every tenant configured.

## Tests and checks

Run the test suite:

```sh
mix test
```

This project defines a `precommit` alias that compiles with warnings as errors, checks for unused deps, formats code, and runs tests:

```sh
mix precommit
```

Use it before opening a PR or pushing significant changes.

## Project layout (brief)

- `lib/ledgr/` — domain contexts and business logic
- `lib/ledgr_web/` — HTTP layer, LiveViews, controllers, and plugs
- `priv/repos/<tenant>/` — migrations and seeds per database
- `assets/` — JavaScript and CSS entrypoints

Operational mix tasks (data repair, resets, production-oriented utilities) are intended for trusted operators and are not documented in this README.
