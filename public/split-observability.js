(() => {
  'use strict';
  if (window.__splitObservabilityInstalled) return;
  window.__splitObservabilityInstalled = true;

  const ENDPOINT = 'https://www.split-llc.com/api/internal/incidents/client';
  const seen = new Map();
  const originalFetch = window.fetch.bind(window);
  const originalError = console.error.bind(console);
  const originalWarn = console.warn.bind(console);
  const ERROR_WORDS = /(error|fail(?:ed|ure)?|exception|invalid|timeout|timed out|not found|forbidden|unauthori[sz]ed|disconnect(?:ed)?|socket|query|unavailable|crash|panic|fatal)/i;

  function clean(value, max = 2400) {
    let text = String(value ?? '');
    text = text.replace(/https?:\/\/[^\s?#]+[?#][^\s]+/gi, (url) => url.split(/[?#]/)[0]);
    text = text.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '<email>');
    text = text.replace(/\+?1?[\s().-]*\d{3}[\s().-]*\d{3}[\s.-]*\d{4}/g, '<phone>');
    text = text.replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/gi, '<id>');
    text = text.replace(/\b(?:eyJ[A-Za-z0-9_-]{20,}|(?:sk|pk|gh[opsu]|xox[baprs]|tskey)[-_][A-Za-z0-9_-]{16,})\b/g, '<credential>');
    text = text.replace(/\s+/g, ' ').trim();
    return text.slice(0, max);
  }

  function safeArg(value) {
    if (value instanceof Error) return `${value.name}: ${value.message}`;
    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') return String(value);
    if (!value || typeof value !== 'object') return String(value ?? '');
    const parts = [];
    for (const key of ['name', 'message', 'code', 'status', 'statusCode', 'operation', 'type']) {
      const candidate = value[key];
      if (candidate !== undefined && candidate !== null && typeof candidate !== 'object') parts.push(`${key}=${candidate}`);
    }
    return parts.length ? parts.join(' ') : Object.prototype.toString.call(value);
  }

  function duplicate(key) {
    const now = Date.now();
    const prior = seen.get(key) || 0;
    seen.set(key, now);
    if (seen.size > 160) {
      for (const [item, at] of seen) if (now - at > 10 * 60 * 1000) seen.delete(item);
    }
    return now - prior < 60 * 1000;
  }

  function send(kind, message, extra = {}) {
    try {
      const safeMessage = clean(message) || 'Browser error';
      const key = `${kind}:${safeMessage.slice(0, 700)}:${extra.operation || ''}`;
      if (duplicate(key)) return;
      const payload = {
        kind,
        message: safeMessage,
        stack: clean(extra.stack || '', 8000),
        url: `${location.origin}${location.pathname}`,
        filename: clean(extra.filename || '', 1000),
        line: Number(extra.line || 0) || 0,
        column: Number(extra.column || 0) || 0,
        operation: clean(extra.operation || '', 500),
        status: Number(extra.status || 0) || 0,
      };
      void originalFetch(ENDPOINT, {
        method: 'POST',
        mode: 'cors',
        credentials: 'omit',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
        keepalive: true,
      }).catch(() => undefined);
    } catch {
      // Observability must never affect application behavior.
    }
  }

  window.addEventListener('error', (event) => {
    const error = event.error instanceof Error ? event.error : null;
    send('browser_error', error?.message || event.message || 'Unhandled browser error', {
      stack: error?.stack,
      filename: event.filename,
      line: event.lineno,
      column: event.colno,
      operation: 'window.error',
    });
  });

  window.addEventListener('unhandledrejection', (event) => {
    const reason = event.reason;
    send('unhandled_rejection', reason instanceof Error ? reason.message : safeArg(reason), {
      stack: reason instanceof Error ? reason.stack : '',
      operation: 'unhandledrejection',
    });
  });

  window.fetch = async (...args) => {
    const requestUrl = typeof args[0] === 'string' ? args[0] : args[0] instanceof URL ? args[0].toString() : args[0]?.url || '';
    if (requestUrl.includes('/api/internal/incidents/client')) return originalFetch(...args);
    try {
      const response = await originalFetch(...args);
      if (response.status >= 500) send('http_5xx', `HTTP ${response.status} from ${clean(requestUrl, 1200)}`, { operation: 'fetch', status: response.status });
      return response;
    } catch (error) {
      send('network_error', error instanceof Error ? error.message : 'Browser network request failed', {
        stack: error instanceof Error ? error.stack : '',
        operation: `fetch ${clean(requestUrl, 1000)}`,
      });
      throw error;
    }
  };

  console.error = (...args) => {
    try { send('ui_error', args.map(safeArg).join(' '), { operation: 'console.error' }); } catch {}
    originalError(...args);
  };

  console.warn = (...args) => {
    try {
      const message = args.map(safeArg).join(' ');
      if (message.startsWith('[GodMode]') || ERROR_WORDS.test(message)) {
        send(message.startsWith('[GodMode]') ? 'background_query_error' : 'ui_error', message, { operation: 'console.warn' });
      }
    } catch {}
    originalWarn(...args);
  };

  function inspectNode(node) {
    if (!(node instanceof Element)) return;
    const candidates = [node, ...node.querySelectorAll('[role="alert"],[aria-live="assertive"],[class*="toast" i],[class*="snackbar" i],[class*="notification" i],[class*="error" i]')];
    for (const el of candidates.slice(0, 40)) {
      const role = el.getAttribute('role') || '';
      const classes = typeof el.className === 'string' ? el.className : '';
      const text = clean(el.textContent || '', 1800);
      const errorSurface = role === 'alert' || /error|danger|snackbar|toast/i.test(classes);
      if (text && errorSurface && (ERROR_WORDS.test(text) || /error|danger/i.test(classes))) {
        send('ui_error', text, { operation: 'ui-notification' });
      }
    }
  }

  function startObserver() {
    if (!document.documentElement) return;
    const observer = new MutationObserver((mutations) => {
      try {
        for (const mutation of mutations) for (const node of mutation.addedNodes) inspectNode(node);
      } catch {}
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', startObserver, { once: true });
  else startObserver();
})();
