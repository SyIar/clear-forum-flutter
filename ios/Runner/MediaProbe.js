(() => {
  const seen = new Set();
  const playAttempts = new WeakMap();
  let autoStart = false;
  try {
    const page = new URL(window.location.href);
    autoStart = page.protocol === 'https:' && !page.username && !page.password && (!page.port || page.port === '443') &&
      ['cyberdrop.cr', 'www.cyberdrop.cr'].includes(page.hostname) && /^\/e\/[A-Za-z0-9_-]{1,128}\/?$/.test(page.pathname);
  } catch (_) {}
  const startPrimary = node => {
    if (!autoStart || node.tagName !== 'VIDEO') return;
    const source = node.currentSrc || node.src || '';
    const prior = playAttempts.get(node);
    if (!node.paused) {
      // Successful playback retires the retry budget before a later manual pause.
      playAttempts.set(node, {source, count: 2});
      return;
    }
    // Start once on insertion and once if a delayed source becomes available.
    // A refusal/manual pause is never fought by an endless autoplay loop.
    if (prior && (prior.source === source || prior.count >= 2)) return;
    playAttempts.set(node, { source, count: (prior?.count || 0) + 1 });
    node.preload = 'auto';
    try { const promise = node.play(); if (promise?.catch) promise.catch(() => {}); } catch (_) {}
  };
  const stopAutoplay = () => { autoStart = false; };
  window.addEventListener('forumNativePlayback', stopAutoplay, {once: true});
  let stopped = false;
  let scheduled = false;
  const scan = () => {
    scheduled = false;
    if (stopped) return;
    let nodes = Array.from(document.querySelectorAll('video,audio'))
      .filter(node => !node.closest('.advertisement,.ad-container,.adContainer,.adsbygoogle,[data-ad-slot]'));
    const primary = nodes.filter(node => node.id === 'main-video');
    if (primary.length) nodes = primary;
    if (nodes.length) startPrimary(nodes[0]);
    for (const node of nodes) {
      const value = node.currentSrc || node.src;
      if (!value || seen.has(value) || seen.size >= 8) continue;
      let url;
      try { url = new URL(value, document.baseURI); } catch (_) { continue; }
      if (url.protocol !== 'https:' || url.username || url.password || (url.port && url.port !== '443') || url.href.length > 8192) continue;
      seen.add(value);
      window.webkit.messageHandlers.mediaCandidate.postMessage({ url: url.href });
      break;
    }
  };
  const schedule = () => {
    if (stopped || scheduled) return;
    scheduled = true;
    setTimeout(scan, 100);
  };
  const observer = new MutationObserver(schedule);
  observer.observe(document.documentElement, {subtree: true, childList: true, attributes: true, attributeFilter: ['src']});
  document.addEventListener('loadedmetadata', schedule, true);
  document.addEventListener('loadeddata', schedule, true);
  const interval = setInterval(scan, 1000);
  window.addEventListener('pagehide', () => {
    stopped = true;
    observer.disconnect();
    clearInterval(interval);
    document.removeEventListener('loadedmetadata', schedule, true);
    document.removeEventListener('loadeddata', schedule, true);
  }, {once: true});
  scan();
})();
