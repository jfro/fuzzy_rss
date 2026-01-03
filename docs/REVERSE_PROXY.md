# Running Behind a Reverse Proxy

FuzzyRss is designed to run behind a TLS-terminating reverse proxy (nginx, Caddy, Traefik, etc.). The proxy handles HTTPS and forwards requests to the application over HTTP.

## Configuration

### Application Configuration

Set these environment variables:

```bash
PHX_HOST=rss.example.com          # Your actual domain
PORT=4000                          # Internal port (app listens here)
PHX_URL_SCHEME=https              # External scheme (default: https)
PHX_URL_PORT=443                  # External port (default: 443)
```

The app will:
- Listen on `http://0.0.0.0:4000` (internal)
- Generate URLs as `https://rss.example.com` (external)

### Nginx Example

```nginx
server {
    listen 80;
    server_name rss.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name rss.example.com;

    ssl_certificate /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location / {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        
        # Required for WebSockets
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Standard proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # Timeouts
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
```

### Caddy Example

Caddy automatically handles HTTPS with Let's Encrypt:

```caddyfile
rss.example.com {
    reverse_proxy localhost:4000
}
```

That's it! Caddy automatically:
- Obtains and renews TLS certificates
- Sets proper proxy headers
- Handles WebSocket upgrades

### Traefik Example (Docker Compose)

```yaml
services:
  fuzzy_rss:
    image: fuzzy_rss:latest
    environment:
      PHX_HOST: rss.example.com
      PORT: 4000
      SECRET_KEY_BASE: your-secret-key
      DATABASE_ADAPTER: sqlite
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.fuzzy_rss.rule=Host(`rss.example.com`)"
      - "traefik.http.routers.fuzzy_rss.entrypoints=websecure"
      - "traefik.http.routers.fuzzy_rss.tls=true"
      - "traefik.http.routers.fuzzy_rss.tls.certresolver=letsencrypt"
      - "traefik.http.services.fuzzy_rss.loadbalancer.server.port=4000"

  traefik:
    image: traefik:v2.10
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.email=your@email.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./letsencrypt:/letsencrypt"
```

## WebSocket Support

Phoenix LiveView requires WebSocket support. All example configurations above handle WebSocket upgrades correctly.

If you see connection errors in the browser console, ensure your proxy:
1. Sets `Upgrade` and `Connection` headers
2. Has sufficient timeout values (300s recommended)
3. Allows WebSocket connections through your firewall

## Testing

After configuring your proxy:

```bash
# Test HTTP → HTTPS redirect
curl -I http://rss.example.com

# Test HTTPS works
curl -I https://rss.example.com

# Check WebSocket connection (in browser console)
# Should show: "LiveView connected"
```

## Troubleshooting

**WebSocket disconnections:**
- Increase proxy timeouts (300s+)
- Verify `Upgrade` and `Connection` headers are set
- Check firewall allows WebSocket connections

**Mixed content warnings:**
- Ensure `PHX_URL_SCHEME=https` is set
- Verify proxy sets `X-Forwarded-Proto: https`

**Origin errors in console:**
- Set `CHECK_ORIGIN=false` (testing only)
- Or set `CHECK_ORIGIN=https://rss.example.com`
- Verify `PHX_HOST` matches your domain
