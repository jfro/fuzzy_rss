# Feed Reader APIs (Fever & Google Reader)

This document covers implementing industry-standard RSS sync APIs for mobile app compatibility.

## Overview

**Goal:** Enable sync with popular mobile RSS readers (Reeder, NetNewsWire, NewsFlash, etc.)

**APIs to Implement:**
1. **Fever API** - Simple, read/star/mark operations only
2. **Google Reader API** - Full-featured with subscription management

---

## API Comparison

| Feature | Google Reader API | Fever API |
|---------|------------------|-----------|
| **Client Support** | Highest (Reeder, NewsFlash, ReadKit, many more) | High (Reeder, Unread, FeedMe, NewsFlash) |
| **Complexity** | High (undocumented, reverse-engineered) | Low-Medium |
| **Features** | Full-featured (subscriptions, tags, streaming) | Basic (read, star, sync) |
| **Authentication** | Dual token (auth + session) | MD5(email:password) API key |
| **Documentation** | Unofficial only | Original spec available |
| **Write Operations** | Full CRUD for subscriptions | Mark read/star only |

---

## Phase 1: Fever API

### Overview

The Fever API uses a single endpoint (`/fever/`) with query parameters. All requests are POST with form-encoded `api_key` for authentication.

**Limitations:** Cannot add/remove feeds via API (original spec limitation, not implementation choice).

### Files to Create

| File | Purpose |
|------|---------|
| `lib/fuzzy_rss_web/controllers/api/fever_controller.ex` | Main Fever API controller |
| `lib/fuzzy_rss_web/plugs/fever_auth.ex` | Authentication plug |
| `lib/fuzzy_rss/api/fever.ex` | Response formatters |
| `priv/repo/migrations/*_add_fever_api_key_to_users.exs` | Migration |
| `test/fuzzy_rss_web/controllers/api/fever_controller_test.exs` | Tests |

### Files to Modify

| File | Changes |
|------|---------|
| `lib/fuzzy_rss/accounts/user.ex` | Add `fever_api_key` field and changeset |
| `lib/fuzzy_rss/accounts.ex` | Add `get_user_by_fever_api_key/1`, `set_fever_api_key/2` |
| `lib/fuzzy_rss/content.ex` | Add Fever-specific queries |
| `lib/fuzzy_rss_web/router.ex` | Add `/fever` route and pipeline |
| `lib/fuzzy_rss_web/live/reader_live/account_settings.ex` | UI to set Fever API password |

### Authentication

Since the app uses magic links/OIDC (no traditional passwords), users set a **dedicated Fever API password**:
- User enters a Fever password in settings
- Server stores `MD5(email:fever_password)` in `users.fever_api_key`
- Clients authenticate with this MD5 hash

### Endpoints

**Route:** `POST /fever/` (single endpoint, actions via query params)

| Query Params | Action |
|--------------|--------|
| `?api` | Auth check - returns `api_version`, `auth` (0/1) |
| `?api&groups` | List folders as groups |
| `?api&feeds` | List subscribed feeds + feeds_groups mapping |
| `?api&items` | List entries (pagination: `since_id`, `max_id`, `with_ids`) |
| `?api&favicons` | Base64 encoded feed favicons |
| `?api&unread_item_ids` | Comma-separated unread entry IDs |
| `?api&saved_item_ids` | Comma-separated starred entry IDs |

**Write Operations (POST body):**

| Params | Action |
|--------|--------|
| `mark=item&as=read&id=X` | Mark entry read |
| `mark=item&as=saved&id=X` | Star entry |
| `mark=item&as=unsaved&id=X` | Unstar entry |
| `mark=feed&as=read&id=X&before=timestamp` | Mark feed read before time |
| `mark=group&as=read&id=X&before=timestamp` | Mark folder read before time |

### Content Context Functions

```elixir
# New functions needed in FuzzyRss.Content:
list_fever_items(user, opts)        # Items with pagination
get_unread_item_ids(user)           # Returns comma-separated IDs
get_saved_item_ids(user)            # Returns comma-separated IDs
get_feeds_groups(user)              # Feed-to-folder mappings
mark_feed_read_before(user, feed_id, timestamp)
mark_folder_read_before(user, folder_id, timestamp)
```

### Database Considerations

The `feeds_groups` query uses aggregation that differs by database:
- SQLite/MySQL: `GROUP_CONCAT(feed_id)`
- PostgreSQL: `string_agg(feed_id::text, ',')`

### Supported Clients

- **iOS:** Reeder, Unread, Lire
- **Android:** FeedMe, FocusReader, Read You
- **macOS:** Reeder, ReadKit
- **Linux:** NewsFlash

---

## Phase 2: Google Reader API

### Overview

Full-featured API with subscription management. Uses multiple endpoints under `/reader/api/0/` with dual-token authentication.

### Files to Create

| File | Purpose |
|------|---------|
| `lib/fuzzy_rss_web/controllers/api/greader_controller.ex` | Main controller |
| `lib/fuzzy_rss_web/controllers/api/greader/auth_controller.ex` | ClientLogin endpoint |
| `lib/fuzzy_rss_web/controllers/api/greader/subscription_controller.ex` | Feed management |
| `lib/fuzzy_rss_web/controllers/api/greader/stream_controller.ex` | Content retrieval |
| `lib/fuzzy_rss_web/controllers/api/greader/tag_controller.ex` | Tags/folders |
| `lib/fuzzy_rss_web/plugs/greader_auth.ex` | Auth plug |
| `lib/fuzzy_rss/api/greader.ex` | Response formatters & ID conversion |

### Authentication Flow

1. **ClientLogin:** `POST /accounts/ClientLogin`
   - Params: `Email`, `Passwd` (Passwd should be the MD5 hash API password, same as Fever API)
   - Returns: `SID=...\nAuth=...` (newline-separated)
   - Store auth token, use in header: `Authorization: GoogleLogin auth={token}`

2. **Session Token:** `GET /reader/api/0/token`
   - Returns 57-char token for state-changing requests
   - Pass as `T` parameter in POST requests

**Note:** Both Fever and Google Reader APIs use the same API password (MD5 hash of `email:password`). This allows users without account passwords (magic link users) to use RSS reader apps.

### Endpoints

**User & Auth:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/accounts/ClientLogin` | POST | Login, get auth token |
| `/reader/api/0/token` | GET | Get session token for writes |
| `/reader/api/0/user-info` | GET | User profile |

**Subscriptions (Full CRUD):**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/reader/api/0/subscription/list` | GET | List all feeds |
| `/reader/api/0/subscription/quickadd` | POST | Add feed by URL |
| `/reader/api/0/subscription/edit` | POST | Edit/unsubscribe feed |

**Tags & Folders:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/reader/api/0/tag/list` | GET | List folders/tags |
| `/reader/api/0/rename-tag` | POST | Rename folder |
| `/reader/api/0/disable-tag` | POST | Delete folder |

**Content Retrieval:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/reader/api/0/stream/contents/:streamId` | GET/POST | Fetch items with content |
| `/reader/api/0/stream/items/ids` | GET | Item IDs only (pagination) |
| `/reader/api/0/stream/items/contents` | POST | Batch fetch by IDs |
| `/reader/api/0/unread-count` | GET | Unread counts per feed |

**State Management:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/reader/api/0/edit-tag` | POST | Mark read/starred |
| `/reader/api/0/mark-all-as-read` | POST | Bulk mark read |

### Stream IDs

| Stream | ID Format |
|--------|-----------|
| All items | `user/-/state/com.google/reading-list` |
| Read items | `user/-/state/com.google/read` |
| Starred | `user/-/state/com.google/starred` |
| Folder | `user/-/label/{folder_name}` |
| Feed | `feed/{feed_url}` |

### Item ID Formats (Must Support All 3)

```
Long hex:  tag:google.com,2005:reader/item/000000000000001F
Short hex: 000000000000001F
Decimal:   31
```

Store as integers internally, convert on input/output.

### Subscription Edit Operations

```
# Subscribe
POST /reader/api/0/subscription/edit
ac=subscribe&s=feed/{url}&t={title}&a=user/-/label/{folder}

# Edit (rename, move to folder)
POST /reader/api/0/subscription/edit
ac=edit&s=feed/{url}&t={new_title}&a=user/-/label/{folder}&r=user/-/label/{old_folder}

# Unsubscribe
POST /reader/api/0/subscription/edit
ac=unsubscribe&s=feed/{url}
```

### Implementation Challenges

1. **Undocumented spec** - Must test against real clients
2. **ID format variations** - Parse all 3 formats
3. **Timestamp formats** - Some fields need int, some string, some ms/μs
4. **Client differences** - Reeder uses IDs→batch content, NewsFlash uses direct stream
5. **Response format** - `edit-tag` must return `text/plain "OK"`

### Supported Clients

- **iOS/macOS:** Reeder 5/Classic, NetNewsWire, ReadKit, Lire
- **Android:** FeedMe, Read You, FocusReader
- **Linux:** NewsFlash
- **Windows:** Fluent Reader

---

## Implementation Steps

### Phase 1: Fever API

1. Create migration for `fever_api_key` field on users
2. Update User schema with field and changeset
3. Add Accounts context functions (`get_user_by_fever_api_key`, `set_fever_api_key`)
4. Create `FeverAuth` plug
5. Add Content context query functions for Fever
6. Create `FuzzyRss.Api.Fever` response formatter module
7. Implement `FeverController` with all endpoints
8. Add `/fever` routes to router
9. Write Fever API tests
10. Add settings UI for Fever password

### Phase 2: Google Reader API

1. Create migration for `greader_auth_token` field on users
2. Add Accounts context functions for GReader auth
3. Create `GReaderAuth` plug (parses `Authorization: GoogleLogin auth=...`)
4. Create `FuzzyRss.Api.GReader` module (ID conversion, formatters)
5. Implement `AuthController` (ClientLogin, token)
6. Implement `SubscriptionController` (list, quickadd, edit)
7. Implement `StreamController` (contents, items/ids, items/contents)
8. Implement `TagController` (list, rename, disable)
9. Implement state endpoints (edit-tag, mark-all-as-read, unread-count)
10. Add `/accounts` and `/reader` routes
11. Write GReader API tests
12. Update settings UI to show GReader endpoint

---

## Testing

### Fever API

1. **Unit tests:** All endpoints, auth, pagination, mark operations
2. **Client testing:** Reeder, NewsFlash, FeedMe
3. **Verify:**
   - Auth with MD5 key works
   - Groups/feeds/items return correctly
   - Mark read/starred syncs bidirectionally
   - Pagination with since_id/max_id works

### Google Reader API

1. **Unit tests:** All endpoints, ID format conversion, auth flow
2. **Client testing:** Reeder, NewsFlash, NetNewsWire
3. **Verify:**
   - ClientLogin returns valid token
   - Subscription CRUD works (add/edit/delete feeds)
   - Folder management works
   - Stream contents pagination works
   - All 3 item ID formats parse correctly
   - `edit-tag` returns `text/plain "OK"`

### Integration

1. Add feeds via Google Reader API, verify they appear in Fever API
2. Mark read in Fever, verify reflected in Google Reader
3. Star in one API, verify in the other
4. Test with real mobile apps end-to-end

---

## References

- [Re-Implementing the Google Reader API in 2025](https://www.davd.io/posts/2025-02-05-reimplementing-google-reader-api-in-2025/)
- [The Old Reader API](https://github.com/theoldreader/api)
- [BazQux API](https://github.com/bazqux/bazqux-api)
- [FreshRSS Fever API](https://freshrss.github.io/FreshRSS/en/developers/06_Fever_API.html)
- [FreshRSS Google Reader API](https://freshrss.github.io/FreshRSS/en/developers/06_GoogleReader_API.html)
- [Fever API (Arsse)](https://thearsse.com/manual/en/Supported_Protocols/Fever.html)
