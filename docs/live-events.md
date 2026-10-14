# Live events

packages.ecosyste.ms can post a webhook each time it records a new package or a new version. The receiver is expected to be an internal service (live.ecosyste.ms) that fans the events out to public SSE/WebSocket clients. This app does no fanout itself; it makes one HTTP POST per sync and moves on.

The feature is off unless `LIVE_WEBHOOK_URL` is set. With it unset the emit methods return immediately, no payloads are built, and no extra queries run.

## Configuration

| Variable | Purpose |
|---|---|
| `LIVE_WEBHOOK_URL` | Full URL of the ingest endpoint. Presence of this enables the feature. |
| `LIVE_WEBHOOK_TOKEN` | Optional. Sent as `Authorization: Bearer <token>` so the receiver can reject unauthenticated posts. |

## When events fire

Events are emitted inline from the sync path, which already runs inside Sidekiq, so there is no extra job.

- [`Registry#sync_package`](../app/models/registry.rb#L198) emits `package.created` after saving a package that did not previously exist.
- [`Registry#sync_package`](../app/models/registry.rb#L219) emits `version.created` for every row inserted via `Version.upsert_all`. The just-inserted versions are reloaded with one query and one POST carries all of them.
- [`Package#update_versions`](../app/models/package.rb#L403) emits `version.created` for any versions it creates.

[`LiveEvent.emit`](../app/lib/live_event.rb#L6) makes the request with a 500ms connect and read timeout and rescues `Faraday::Error`. The emit methods on `Package` additionally rescue any `StandardError` raised while building the payload, so a slow or dead receiver adds at most half a second to a sync and a serialisation bug never causes one to fail. Delivery is fire-and-forget with no retries; this is a live ticker, not a durable log, so a dropped event is acceptable.

## Request

```
POST $LIVE_WEBHOOK_URL
Content-Type: application/json
User-Agent: packages.ecosyste.ms
Authorization: Bearer $LIVE_WEBHOOK_TOKEN
```

```json
{
  "events": [
    {
      "event": "version.created",
      "registry": "rubygems.org",
      "registry_url": "https://packages.ecosyste.ms/api/v1/registries/rubygems.org",
      "package_url": "https://packages.ecosyste.ms/api/v1/registries/rubygems.org/packages/rails",
      "version_url": "https://packages.ecosyste.ms/api/v1/registries/rubygems.org/packages/rails/versions/8.1.1",
      "package": {
        "id": 123,
        "name": "rails",
        "ecosystem": "rubygems",
        "purl": "pkg:gem/rails",
        "registry_url": "https://rubygems.org/gems/rails",
        "...": "..."
      },
      "version": {
        "id": 456,
        "number": "8.1.1",
        "published_at": "2026-06-15T14:03:11Z",
        "purl": "pkg:gem/rails@8.1.1",
        "download_url": "https://rubygems.org/downloads/rails-8.1.1.gem",
        "registry_url": "https://rubygems.org/gems/rails/versions/8.1.1",
        "...": "..."
      }
    }
  ]
}
```

`events` is always an array. A `package.created` event has `registry_url`, `package_url` and `package` but no `version_url` or `version`.

The `package` and `version` objects use the same field names as the [`Package`](../openapi/api/v1/openapi.yaml) and `Version` schemas in the public API, minus the parts that would cost extra queries to produce: `maintainers`, `dependencies`, the large `repo_metadata`/`metadata`/`advisories`/`issue_metadata` blobs on the package, and the route-helper `*_url` fields. See [`Package::LIVE_EVENT_ATTRS`](../app/models/package.rb#L217) and [`Version::LIVE_EVENT_ATTRS`](../app/models/version.rb#L167) for the exact lists.

A consumer that wants any of the omitted data follows `registry_url`, `package_url` or `version_url`, which return the full API representation including dependencies, maintainers, and repo metadata. The inline objects carry enough (name, ecosystem, purl, description, download URL, published timestamp) to filter and display without round-tripping for every event.

## Receiver expectations

The receiver should respond quickly with any 2xx status; the body is ignored. It should validate the bearer token, assign each incoming event a monotonic id, keep a short ring buffer for `Last-Event-ID` replay, and broadcast to connected SSE clients with a heartbeat comment roughly every 25 seconds to keep Cloudflare from closing idle streams.
