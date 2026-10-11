# Signature native plugin

Owner-only native Codex workspace using the existing authenticated Signature REST API. The API projection and launcher live here. The shared MCP transport and renderer come from `split-payments-website/native-plugins`; its package generator creates this manifest, assets, skills and `dist/signature.html`.

See that package README for installation, owner binding, action receipts, acceptance limits and rollback. No Rails routes, customer signing pages, document records or delivery jobs are changed by installing this plugin. The existing template designer remains available.

Run `node --test native-plugin/test/*.test.mjs` from this repository for API projection and identifier checks.
