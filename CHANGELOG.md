# Changelog

All notable changes to the **BookReview** project will be documented in this file.

This changelog covers all four repositories that make up the project:

- [`bookreview`](https://github.com/andreimitea30/bookreview) — main repo (orchestration, gateway, monitoring, CI/CD)
- [`bookreview-auth`](https://github.com/andreimitea30/bookreview-auth) — Auth Service (submodule)
- [`bookreview-io`](https://github.com/andreimitea30/bookreview-io) — IO Service (submodule)
- [`bookreview-business`](https://github.com/andreimitea30/bookreview-business) — Business Logic Service (submodule)

---

## Unreleased

The items below are described in the project specification but are **not yet implemented**.
They will be addressed in the following milestone.

### To Be Added

- **Kong rate limiting.** The current `kong/kong.yml` only configures routing; the
  `rate-limiting` plugin still needs to be added per route.
- **Grafana dashboards provisioning.** Grafana is deployed but starts empty — datasource and a
  Flask-apps dashboard must be auto-provisioned via files under
  `monitoring/grafana/provisioning/`.
- **Validating end-to-end CI/CD deploy.** GitHub Actions workflows exist in all four repos,
  but the full `build → push to Docker Hub → SSH deploy on Swarm manager` chain has not
  yet been executed against a real Swarm cluster.
- **Publish images on Docker Hub.** `docker-stack.yml` references
  `andreimitea30/bookreview-{auth,io,business,auth-db,books-db}:latest`; these images need
  to be built and pushed by the per-service workflows so the Swarm stack can pull them.

### To Be Fixed

- Per-service GitHub Actions workflows currently trigger on branch `initial_try` instead
  of `main` — needs to be flipped before the CI/CD chain becomes useful on the default
  branch.

---

## 0.1.0 — 2026-04-11

Second milestone release (**Etapa II**). Delivers the full backend stack, monitoring,
gateway, and CI/CD scaffolding.

### Added

#### Microservices (Python 3.11 + Flask)

- **Auth Service** (`bookreview-auth`, port 5000) — `POST /auth/register`,
  `POST /auth/login`, `POST /auth/validate`, `GET /health`. Passwords hashed with
  `bcrypt`; JWTs (HS256, 24h expiry) issued and verified via `PyJWT`. Connects to
  `auth-db` (MariaDB) through `PyMySQL` with a 5-attempt connect-retry loop.
- **IO Service** (`bookreview-io`, port 5001) — sole owner of the books database.
  `GET /books` (with optional `?q=` title/author search), `GET /books/<id>`,
  `GET /books/<id>/reviews`, `POST /reviews`, `GET /health`. On review insert,
  recalculates and persists `avg_rating` and `review_count` for the affected book in
  the same transaction.
- **Business Logic Service** (`bookreview-business`, port 5002) — proxies `/api/books*`
  to IO, and on `POST /api/reviews` validates the JWT against Auth Service, censors
  profanity in the comment with `better-profanity`, then forwards the cleaned review
  to IO. `GET /health`.

#### Databases

- Two **MariaDB 11** instances, isolated on separate Docker networks:
  - `auth-db` with `users(id, username, email, password_hash, created_at)`.
  - `books-db` with `books(id, title, author, description, avg_rating, review_count, created_at)`
    and `reviews(id, book_id, user_id, username, rating, comment, created_at)`,
    seeded with 5 classic books.
- Healthchecks on both DBs (`mariadb-admin ping`) so service containers wait for the
  DB to be ready.
- **Adminer 4** included for visual inspection of both schemas at port 8080.

#### API Gateway

- **Kong 3.6** running DB-less, configured declaratively via `kong/kong.yml`. Routes
  `/auth/*` → auth-service and `/api/*` → business-logic-service. Public proxy on
  port 8000, admin API on 8001.

#### Monitoring

- **Prometheus v2.51.2** scraping `/metrics` (exposed by `prometheus-flask-exporter`)
  from all three Flask services every 15s.
- **Grafana 10.4.2** deployed alongside Prometheus with admin/admin default credentials
  and a persistent volume for dashboards.
- **Portainer CE 2.20.3** for visual cluster management.

#### Orchestration

- `docker-compose.yml` for local development: brings up all 10 containers
  (2 DBs, Adminer, 3 services, Kong, Prometheus, Grafana, Portainer) on four isolated
  bridge networks (`auth-network`, `app-network`, `gateway-network`,
  `monitoring-network`).
- `docker-stack.yml` for **Docker Swarm** deployment: same topology with overlay
  networks; DBs and stateful services pinned to the manager node, microservices
  scheduled on workers; `business-logic-service` scaled to 2 replicas; rolling-update
  config with `failure_action: rollback` on every service.

#### CI/CD

- Per-service GitHub Actions `Build & Push` workflows (`bookreview-auth`,
  `bookreview-io`, `bookreview-business`) that build the service image (and DB image
  where applicable) and push to Docker Hub on every commit, tagged with both `latest`
  and the commit SHA.
- Main-repo workflow (`bookreview/.github/workflows/ci-cd.yml`) that, on push to
  `main`, copies the stack files to the Swarm manager via `scp` and runs
  `docker stack deploy` over `ssh`.

#### Documentation

- `README.md` covering architecture, local Compose run, Swarm cluster setup, CI/CD
  secrets, and team responsibilities.

### Project structure

- Code split across **4 separate repositories** (1 orchestration + 3 microservices) per
  project requirements.


### Changed (2026-04-24)

- The three microservice repos are now tracked as **git submodules** inside the main
  `bookreview` repo at `auth-service/`, `io-service/`, and `business-logic-service/`,
  pinned to branch `initial_try`. Cloning the main repo with
  `git clone --recurse-submodules` now lands all four repos in the layout
  `docker-compose.yml` expects, so `docker compose up --build -d` works on any
  developer machine without manual setup.
- `README.md` updated with `--recurse-submodules` clone instructions.

---

## Workload Management

### Bianca Scîrtocea

- IO Service implementation
- Business Logic implementation
- DB schema + Adminer
- Prometheus + Grafana deploy

### Andrei Mitea

- Auth Service implementation
- Kong
- Main CI/CD deploy
- Docker Hub + secrets
- Submodules splits