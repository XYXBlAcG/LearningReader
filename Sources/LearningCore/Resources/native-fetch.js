(function () {
  'use strict';
  const bridge = window.webkit?.messageHandlers?.readerResource;
  if (!bridge) return;
  const original = window.fetch.bind(window);
  window.fetch = async function (input, options = {}) {
    const url = new URL(input instanceof Request ? input.url : String(input), window.location.href);
    if (url.protocol !== 'mathreader:') return original(input, options);
    const method = options.method || (input instanceof Request ? input.method : 'GET');
    if (method !== 'GET') throw new TypeError('Local reader resources are read-only');
    const signal = options.signal || (input instanceof Request ? input.signal : undefined);
    if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
    const result = await bridge.postMessage({url: url.href});
    if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
    const body = Uint8Array.from(atob(result.body), value => value.charCodeAt(0));
    return new Response(body, {status: result.status, headers: {'Content-Type': result.mime}});
  };
})();
