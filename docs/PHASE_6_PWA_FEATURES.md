# Phase 6: PWA Features

**Duration:** Week 5 (2 days)
**Previous Phase:** [Phase 5: LiveView UI](PHASE_5_LIVEVIEW_UI.md)
**Next Phase:** [Phase 7: REST API](PHASE_7_REST_API.md)

## Overview

Add Progressive Web App (PWA) features for mobile support, offline capability, and installability.

## 6.1: Web App Manifest

Create `priv/static/manifest.json`:

```json
{
  "name": "FuzzyRSS - RSS Aggregator",
  "short_name": "FuzzyRSS",
  "description": "A modern RSS aggregator with multi-user support",
  "start_url": "/app",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#fd7e14",
  "orientation": "portrait-primary",
  "icons": [
    {
      "src": "/images/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "/images/icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "/images/icon-maskable-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable"
    }
  ],
  "screenshots": [
    {
      "src": "/images/screenshot-540.png",
      "sizes": "540x720",
      "type": "image/png",
      "form_factor": "narrow"
    },
    {
      "src": "/images/screenshot-1280.png",
      "sizes": "1280x720",
      "type": "image/png",
      "form_factor": "wide"
    }
  ],
  "categories": ["news", "productivity"],
  "shortcuts": [
    {
      "name": "View Unread",
      "short_name": "Unread",
      "description": "View unread articles",
      "url": "/app?view=unread",
      "icons": [{"src": "/images/icon-96.png", "sizes": "96x96"}]
    }
  ]
}
```

Update `lib/fuzzy_rss_web/components/layouts/root.html.heex`:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />

    <!-- PWA Manifest & Meta Tags -->
    <link rel="manifest" href="/manifest.json" />
    <link rel="icon" type="image/png" href="/images/icon-192.png" />
    <link rel="apple-touch-icon" href="/images/icon-192.png" />
    <meta name="theme-color" content="#fd7e14" />
    <meta name="apple-mobile-web-app-capable" content="yes" />
    <meta name="apple-mobile-web-app-status-bar-style" content="default" />
    <meta name="apple-mobile-web-app-title" content="FuzzyRSS" />

    <title>FuzzyRSS</title>

    <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>
  </head>

  <body>
    <%= @inner_content %>
  </body>
</html>
```

## 6.2: Service Worker

Create `priv/static/sw.js` (place in public static folder):

```javascript
const CACHE_VERSION = 'fuzzyrss-v1';
const CACHE_NAME = `${CACHE_VERSION}-cache`;
const URLS_TO_CACHE = [
  '/app',
  '/assets/app.css',
  '/assets/app.js',
  '/offline.html'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[ServiceWorker] Caching app shell');
      return cache.addAll(URLS_TO_CACHE);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            console.log('[ServiceWorker] Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  // Skip non-GET requests
  if (event.request.method !== 'GET') {
    return;
  }

  // For navigation requests, try network first, fall back to cache
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .catch(() => caches.match('/offline.html'))
    );
    return;
  }

  // For other requests, cache first, fall back to network
  event.respondWith(
    caches.match(event.request).then((response) => {
      if (response) {
        return response;
      }

      return fetch(event.request).then((response) => {
        // Cache successful responses
        if (!response || response.status !== 200 || response.type === 'error') {
          return response;
        }

        const responseToCache = response.clone();
        caches.open(CACHE_NAME).then((cache) => {
          cache.put(event.request, responseToCache);
        });

        return response;
      });
    })
  );
});
```

Register service worker in `assets/js/app.js`:

```javascript
// At the end of the file:
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker
      .register('/sw.js')
      .then((reg) => {
        console.log('Service Worker registered:', reg);
      })
      .catch((err) => {
        console.error('Service Worker registration failed:', err);
      });
  });
}
```

## 6.3: Mobile-Responsive UI

Update theme switching and responsive layout in `lib/fuzzy_rss_web/live/reader_live/index.html.heex`:

```heex
<div class="flex flex-col lg:flex-row h-screen">
  <!-- Sidebar: hidden on mobile, sticky on desktop -->
  <div class="hidden lg:block lg:w-64 lg:sticky lg:top-0">
    <.live_component module={FuzzyRssWeb.ReaderLive.Sidebar} id="sidebar" {...assigns} />
  </div>

  <!-- Mobile hamburger menu -->
  <div class="lg:hidden flex items-center border-b bg-base-100 p-2">
    <label for="sidebar-drawer" class="btn btn-ghost drawer-button">
      <.icon name="hero-bars-3" class="h-6 w-6" />
    </label>
  </div>

  <!-- Main content -->
  <div class="flex-1 flex flex-col min-w-0">
    <.live_component module={FuzzyRssWeb.ReaderLive.EntryList} id="entry_list" {...assigns} />

    <!-- Entry detail: modal on mobile, sidebar on desktop -->
    <% if assigns.selected_entry do %>
      <div class="hidden lg:block lg:w-96 lg:border-l overflow-y-auto">
        <.live_component module={FuzzyRssWeb.ReaderLive.EntryDetail} id="entry_detail" {...assigns} />
      </div>

      <!-- Mobile modal for entry detail -->
      <div class="lg:hidden fixed inset-0 z-40 bg-black/50" phx-click="close_entry"></div>
      <div class="lg:hidden fixed inset-0 z-50 overflow-y-auto">
        <.live_component module={FuzzyRssWeb.ReaderLive.EntryDetail} id="entry_detail_mobile" {...assigns} />
      </div>
    <% end %>
  </div>
</div>
```

Add to mobile CSS in `assets/css/app.css`:

```css
@media (max-width: 768px) {
  .entry-card {
    padding: 0.75rem;
  }

  .prose {
    font-size: 0.875rem;
  }

  /* Touch-friendly tap targets */
  button, a, .btn {
    min-height: 44px;
    min-width: 44px;
  }
}
```

## 6.4: Create Icons

Generate PWA icons:
- 192x192 - `priv/static/images/icon-192.png`
- 512x512 - `priv/static/images/icon-512.png`
- 192x192 maskable - `priv/static/images/icon-maskable-192.png` (for adaptive icons)
- Screenshots - `priv/static/images/screenshot-*.png`

## Completion Checklist

- [ ] Created `priv/static/manifest.json`
- [ ] Updated root layout with PWA meta tags
- [ ] Created `priv/static/sw.js` service worker
- [ ] Registered service worker in `assets/js/app.js`
- [ ] Added mobile-responsive Flexbox layout
- [ ] Created PWA icons (192x192, 512x512, maskable)
- [ ] Tested on mobile device/emulator
- [ ] Verified PWA installable: Chrome DevTools > Lighthouse

## Testing PWA Features

```bash
# Run app
mix phx.server

# Test on mobile:
# 1. Chrome DevTools (F12) > Application > Manifest
# 2. Install button should appear (Android Chrome)
# 3. Test offline: DevTools > Network > Offline
```

## Next Steps

Proceed to [Phase 7: REST API](PHASE_7_REST_API.md).
