// Minimal Chrome DevTools Protocol helper (no Playwright), using Node's built-in fetch/WebSocket.
module.exports.cdp = async (port = 9222) => {
  const list = async () =>
    (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const evalIn = async (match, expr) => {
    const t = (await list()).find((t) => t.type === 'page' && match(t.url));
    if (!t) return { missing: true };
    const ws = new WebSocket(t.webSocketDebuggerUrl);
    await new Promise((r) => ws.addEventListener('open', r, { once: true }));
    const res = await new Promise((r) => {
      ws.addEventListener('message', (m) => {
        const d = JSON.parse(m.data);
        if (d.id === 1) r(d.result);
      });
      ws.send(
        JSON.stringify({
          id: 1,
          method: 'Runtime.evaluate',
          params: { expression: expr, awaitPromise: true, returnByValue: true },
        }),
      );
    });
    ws.close();
    return res.result?.value;
  };
  return { list, evalIn };
};
