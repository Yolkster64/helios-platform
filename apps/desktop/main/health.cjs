function healthUrl(base) {
  const url = new URL(base);
  if (url.protocol !== 'http:' || !['127.0.0.1', '[::1]'].includes(url.hostname)
      || url.username || url.password || url.pathname !== '/' || url.search || url.hash) {
    throw new Error('Set HELIOS_AIHUB_URL to an explicit HTTP loopback root.');
  }
  return new URL('/healthz', url).href;
}

async function checkHealth(base, fetchImpl = fetch) {
  const checkedAt = new Date().toISOString();
  if (!base) return { state: 'disabled', detail: 'Set HELIOS_AIHUB_URL to check your local AIHub. No endpoint is scanned automatically.', checkedAt };
  let url;
  try { url = healthUrl(base); } catch {
    return { state: 'unavailable', detail: 'HELIOS_AIHUB_URL must be an HTTP loopback root such as http://127.0.0.1:5080.', checkedAt };
  }
  try {
    const response = await fetchImpl(url, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(4000), headers: { Accept: 'application/json' } });
    if (!response.ok) { await response.body?.cancel(); throw new Error('Health request failed'); }
    if (!response.headers.get('content-type')?.includes('application/json')) { await response.body?.cancel(); throw new Error('Expected JSON'); }
    const reader = response.body.getReader();
    let size = 0;
    const parts = [];
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 65536) { await reader.cancel(); throw new Error('Response too large'); }
      parts.push(Buffer.from(value));
    }
    const payload = JSON.parse(Buffer.concat(parts).toString('utf8'));
    if (payload?.status !== 'ok') throw new Error('Unexpected health response');
    return { state: 'ready', detail: 'Local AIHub health endpoint responded. Provider authentication and connector readiness are not verified by this check.', checkedAt };
  } catch {
    return { state: 'unavailable', detail: 'AIHub health check failed. Confirm the local service, endpoint, and JSON response; no credentials were sent.', checkedAt };
  }
}

module.exports = { healthUrl, checkHealth };
