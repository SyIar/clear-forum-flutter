# Simp browser-verification recovery

Simp can return a DDoS-Guard document at the requested thread URL, with either a
success or error HTTP status. The reader previously recognized Cloudflare only,
so the DDoS-Guard document became an unsupported/forbidden/network error.

## Behavior

- Recognize the DDoS-Guard title and `ddg-*` DOM markers before ordinary HTTP
  permission/server errors. Preserve rate limiting, login, and ordinary errors.
  Apply the same classification to search forms and results.
- A foreground reader opens the existing native site browser once per failed
  page attempt. This includes adjacent-page loading. Explicit Retry or a new page
  navigation allows another attempt; cancelling does not reopen the cover.
- Use the existing persistent WebKit data store and browser identity. WebKit
  performs the site's normal navigation and scripts. No challenge solver,
  fabricated verification cookie, or search POST replay is involved.
- Observe the DOM for up to 90 seconds. Automatically return only after a real
  forum page at the requested origin and page identity parses successfully.
  Navigation callbacks also inspect completed pages. Human challenges remain
  visible for the user, with the existing Done and Read page actions available.
- Preserve the visible page window when verification interrupts seamless paging,
  then join the verified neighboring page. Clear the request cache when entering
  and leaving the browser and complete a cookie-store round trip before returning.
- Background library checks report verification without presenting browser UI.
  Manual site-browser visits also return automatically if a detected challenge
  resolves into the originally requested readable page.

## Validation and limits

Regression fixtures cover the supplied DDoS-Guard structure, HTTP 200/403/503,
rate-limit precedence, missing titles, existing Cloudflare checks, quoted markup
inside posts, ordinary errors, search validation, and return-page/origin checks.
Fixtures contain no request IDs, IP addresses, or user-session data.

The macOS workflow is required for Swift tests and device compilation. Actual
challenge completion depends on the website and must be verified on the device;
synthetic parser tests do not prove that a remote challenge will grant access.

Existing localized messages are reused. No new Chinese runtime strings, encoded
Chinese literals, or LEO keys are introduced, and no configuration rollout is
required.

Apple documents the shared WebKit storage mechanism in
[WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore)
and [WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore).
