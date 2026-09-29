(() => {
  'use strict';
  if (window.top !== window || location.origin !== 'https://gofile.io') return;
  const originalFetch = window.fetch;
  const generation = '__FORUM_GENERATION__';
  const fields = ['id', 'name', 'type', 'size', 'mimetype', 'link', 'thumbnail', 'canAccess', 'isFrozen', 'overloaded'];
  const pick = value => {
    const out = {};
    for (const key of fields) {
      const v = value?.[key];
      if (typeof v === 'string') out[key] = v.slice(0, key === 'link' || key === 'thumbnail' ? 8192 : 512);
      else if (typeof v === 'boolean' || (typeof v === 'number' && Number.isFinite(v))) out[key] = v;
    }
    return out;
  };
  const publish = async (response, url) => {
    try {
      if (Number(response.headers.get('content-length')) > 4 * 1024 * 1024) return;
      const body = await response.text();
      if (body.length > 4 * 1024 * 1024) return;
      const envelope = JSON.parse(body);
      const source = envelope.data ?? {};
      const data = pick(source);
      const children = source.canAccess === false ? [] : (source.type === 'file' ? [source] : Object.values(source.children ?? {}));
      // No account data, tokens, request headers, passwords, or server messages cross the bridge.
      data.children = children.length > 1000 ? [] : children.map(pick);
      window.webkit.messageHandlers.gofile.postMessage({
        generation,
        contentId: decodeURIComponent(url.pathname.split('/')[2]),
        page: Number(url.searchParams.get('page') || 1),
        status: envelope.status === 'ok' && children.length <= 1000 ? 'ok' : 'error',
        totalPages: Number(envelope.metadata?.totalPages || 1), data
      });
    } catch (_) { /* The native timeout offers the website when the format changes. */ }
  };
  window.fetch = async function (...args) {
    const response = await originalFetch.apply(this, args);
    try {
      const input = args[0];
      const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, location.href);
      const method = String(args[1]?.method || input?.method || 'GET').toUpperCase();
      if (method === 'GET' && url.origin === 'https://api.gofile.io' && /^\/contents\/[A-Za-z0-9_-]+$/.test(url.pathname)) {
        void publish(response.clone(), url);
      }
    } catch (_) { /* Preserve the site's original request behavior. */ }
    return response;
  };
})();
