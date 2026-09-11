# Signature runtime address contract

The private `split-target-docuseal-data` network reserves `172.30.61.2` for Postgres, `.3` for Redis, and `.4` for the app. The app previously used dynamic allocation and took Redis's address after reboot. Repeated Redis starts then failed, while automatic dependent restarts caused more interruptions.

`split-target-docuseal-network` pins the existing app container to `.4` without recreating containers or touching volumes. It preserves aliases, restores previous connectivity if attachment fails, and refuses an unexpected owner of `.4`. The proxy unit runs this idempotent check before resolving its target address. Keep this helper installed whenever updating the proxy service:

```sh
sudo install -m 755 deploy/split-target-docuseal-network /usr/local/libexec/split-target-docuseal-network
sudo install -m 644 deploy/split-target-docuseal-app-proxy.service /etc/systemd/system/split-target-docuseal-app-proxy.service
sudo systemctl daemon-reload
sudo systemctl restart split-target-docuseal-app-proxy.service
python3 -m unittest discover -s deploy -p 'test_network.py'
```

Verify all three container addresses and health, then `https://sign.split-llc.com/` and `/api/agent/readiness.json`. A successful process start alone does not prove signing-service readiness. Never send a signing packet as a health check.
