# Split HQ API

The native API is exported from `docs/openapi.json`, all routed API extensions,
and the current controller/source fingerprints into
`contracts/hq-api.openapi.json`. This is the source consumed by the global
`@split/sdk` `sign` namespace, shared JavaScript/Python/CLI/MCP clients,
and `/api/agent/openapi.json`. Existing `X-Auth-Token`, account authorization,
object ownership, and signing/SMS evidence rules remain authoritative.

```sh
python3 script/export_hq_api.py
python3 script/export_hq_api.py --check
ruby script/test_hq_api.rb
```

Review API route/controller changes before exporting. All 22 documented API
operations and 14 existing routed extensions are represented. Unknown
extension-body fields remain explicitly validated by the original Rails
handler. No synthetic signing or provider-verification evidence is valid.

The HQ discovery overlay deployer accepts a clean full reviewed revision:

```sh
python3 script/deploy_hq_api.py --revision FULL_SHA
```

It snapshots the existing runtime filesystem, stores the original container
configuration privately under `~/.local/state/split-sign/hq-releases/`, builds
an immutable overlay image containing only the four reviewed discovery/schema/
view files, and preserves the exact existing environment, networks and volumes.
A failed readback restores the prior container. Successful receipts retain the
previous filesystem image plus original configuration for recovery. It does not
change the database schema, templates, merchant documents or signing links.
