# Import/Export Features - Reference Guide

This document provides a quick reference for OPML and FreshRSS JSON import/export functionality. For detailed implementation, see the phase documents listed below.

## Overview

FuzzyRSS supports two import/export formats for data portability:
- **OPML** - Standard RSS subscription format (import/export subscriptions and folder structure)
- **FreshRSS JSON** - Import/export starred articles (compatible with FreshRSS)

---

## Implementation Guide

### Phase 4: Feed Processing Services

**Location**: [Phase 4: Feed Processing](PHASE_4_FEED_PROCESSING.md#opml-importexport-service)

Implements the core import/export logic:

**OPML Service** (`lib/fuzzy_rss/feeds/opml.ex`)
- `export(user)` - Generates OPML XML with subscriptions and folders
- `import(xml_string, user)` - Parses OPML and creates subscriptions/folders
- Handles folder structure recursively

**FreshRSS JSON Service** (`lib/fuzzy_rss/feeds/freshrss_json.ex`)
- `export_starred(user)` - Exports starred articles as JSON
- `import_starred(json_string, user)` - Imports starred articles from JSON
- Matches articles by feed URL and entry URL

---

### Phase 5: LiveView UI

**Location**: [Phase 5: LiveView UI - Settings & Import/Export UI](PHASE_5_LIVEVIEW_UI.md#54-settings--importexport-ui)

Implements the web interface for import/export:

**SettingsLive.ImportExport** (`lib/fuzzy_rss_web/live/settings_live/import_export.ex`)
- Export OPML subscriptions as downloadable file
- Import OPML subscriptions from file upload
- Export starred articles as JSON
- Import starred articles from file upload
- Flash messages for user feedback

**UI Components**
- File upload inputs for OPML and JSON
- Download buttons for export
- Success/error notifications
- Helpful info cards

**JavaScript Handler** (`assets/js/app.js`)
- Client-side file download functionality

---

### Phase 7: REST API

**Location**: [Phase 7: REST API - Import/Export Endpoints](PHASE_7_REST_API.md)

Implements API endpoints for import/export:

**OPML Controller** (`lib/fuzzy_rss_web/controllers/api/v1/opml_controller.ex`)
- `GET /api/v1/opml/export` - Download OPML file
- `POST /api/v1/opml/import` - Upload and import OPML file

**FreshRSS JSON Controller** (`lib/fuzzy_rss_web/controllers/api/v1/freshrss_json_controller.ex`)
- `GET /api/v1/freshrss/starred/export` - Download starred articles JSON
- `POST /api/v1/freshrss/starred/import` - Upload and import starred articles

---

## Quick Integration Checklist

### Phase 4 Tasks
- [ ] Create `lib/fuzzy_rss/feeds/opml.ex` with export/import functions
- [ ] Create `lib/fuzzy_rss/feeds/freshrss_json.ex` with starred article handlers
- [ ] Test with various OPML files from other RSS readers

### Phase 5 Tasks
- [ ] Create `lib/fuzzy_rss_web/live/settings_live/import_export.ex` component
- [ ] Create corresponding `.html.heex` template
- [ ] Add download handler to `assets/js/app.js`
- [ ] Test file uploads and downloads

### Phase 7 Tasks
- [ ] Create `lib/fuzzy_rss_web/controllers/api/v1/opml_controller.ex`
- [ ] Create `lib/fuzzy_rss_web/controllers/api/v1/freshrss_json_controller.ex`
- [ ] Add routes to `lib/fuzzy_rss_web/router.ex`
- [ ] Test API endpoints with curl commands

---

## File Formats

### OPML Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>FuzzyRSS</title>
    <dateCreated>2025-12-29T12:00:00Z</dateCreated>
    <ownerName>user@example.com</ownerName>
  </head>
  <body>
    <!-- Root-level feeds -->
    <outline type="rss" text="Feed Title" xmlUrl="https://example.com/feed" />

    <!-- Folders with nested feeds -->
    <outline type="folder" text="Folder Name">
      <outline type="rss" text="Feed Title" xmlUrl="https://example.com/feed" />
    </outline>
  </body>
</opml>
```

### FreshRSS JSON Structure

```json
{
  "articles": [
    {
      "id": 123,
      "title": "Article Title",
      "url": "https://example.com/article",
      "author": "Author Name",
      "content": "Article content here",
      "summary": "Article summary",
      "published_at": "2025-12-29T12:00:00Z",
      "feed_url": "https://example.com/feed",
      "feed_title": "Feed Title"
    }
  ]
}
```

---

## Use Cases

### Backup & Restore
- Export OPML regularly to backup feed subscriptions
- Export starred articles to preserve saved content
- Restore by importing files after migration or account recovery

### Switch RSS Readers
- Export OPML from FuzzyRSS
- Import into another RSS reader (Feedly, Inoreader, etc.)
- Seamless transition between services

### FreshRSS Migration
- Export starred articles from FreshRSS as JSON
- Import into FuzzyRSS to preserve saved articles
- OPML import works with any RSS reader

### Bulk Operations
- Reorganize feeds via OPML file editing
- Batch import feeds from other sources
- API-driven automation for deployment/provisioning

---

## API Examples

### Export OPML via API

```bash
curl http://localhost:4000/api/v1/opml/export \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -o subscriptions.opml
```

### Import OPML via API

```bash
curl -X POST http://localhost:4000/api/v1/opml/import \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@subscriptions.opml"
```

Response:
```json
{
  "success": true,
  "created_feeds": 15,
  "created_folders": 3,
  "errors": []
}
```

### Export Starred Articles via API

```bash
curl http://localhost:4000/api/v1/freshrss/starred/export \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -o starred.json
```

### Import Starred Articles via API

```bash
curl -X POST http://localhost:4000/api/v1/freshrss/starred/import \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@starred.json"
```

Response:
```json
{
  "success": true,
  "imported": 42,
  "errors": 2
}
```

---

## Notes

- OPML import creates folders and feeds as needed
- Duplicate feeds are handled gracefully (skipped or updated)
- Starred article import matches by feed URL + entry URL
- All import/export operations are user-scoped (isolated per user)
- Import/export is available via both LiveView UI and REST API

---

## See Also

- [Phase 4: Feed Processing](PHASE_4_FEED_PROCESSING.md) - Services
- [Phase 5: LiveView UI](PHASE_5_LIVEVIEW_UI.md) - UI Components
- [Phase 7: REST API](PHASE_7_REST_API.md) - API Endpoints
- [OPML Specification](http://www.opml.org/) - External reference
