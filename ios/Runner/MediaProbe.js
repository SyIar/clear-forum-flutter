(() => {
  const seen = new Set();
  let stopped = false;
  let scheduled = false;
  const scan = () => {
    scheduled = false;
    if (stopped) return;
    let nodes = Array.from(document.querySelectorAll('video,audio'))
      .filter(node => !node.closest('.advertisement,.ad-container,.adContainer,.adsbygoogle,[data-ad-slot]'));
    const primary = nodes.filter(node => node.id === 'main-video');
    if (primary.length) nodes = primary;
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
