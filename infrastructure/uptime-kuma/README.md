# Uptime Kuma

Uptime Kuma runs in a Proxmox LXC (example: CT `<vmid>` on `<node>`).

## Service details

- Hostname: `uptime-kuma`
- Address: `<lxc-ip>`
- Web interface: `http://uptime.example.lan:3001`
- Direct address: `http://<lxc-ip>:3001`
- Deployment directory: `/opt/uptime-kuma`
- Persistent data: `/opt/uptime-kuma/data`
- Container image: `louislam/uptime-kuma:2`
- Bind address: set `UPTIME_KUMA_BIND_IP` (in a `.env` beside `compose.yaml`) to the LXC's LAN IP; it defaults to `127.0.0.1`, so the UI is not exposed until you choose an interface.

## Operations

```bash
cd /opt/uptime-kuma
docker compose pull
docker compose up -d
docker compose logs --tail 100
```

The LXC starts with Proxmox and Docker restarts Uptime Kuma automatically.

## Monitoring

The `Network and Internet` group contains independent checks for:

- LAN gateway reachability
- Cloudflare and Google internet reachability
- Local and public DNS resolution
- Home Assistant over its internal address and public HTTPS endpoint
- Home Assistant certificate expiry

Home Assistant uses its official Uptime Kuma integration with a dedicated API
key. The generated monitor devices are assigned to the `Infrastructure` area.
The local admin credentials and API key are stored outside the repository at
`~/.config/uptime-kuma/admin.env`.
