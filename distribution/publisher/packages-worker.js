// Cloudflare edge TLS for the Azure static package website. The worker only
// forwards public APT objects and never sees the signing key.
const ORIGIN = 'https://broospackagesapp.z5.web.core.windows.net';

export default {
  async fetch(request) {
    const incoming = new URL(request.url);
    if (incoming.hostname !== 'packages.broos.app' ||
        !incoming.pathname.startsWith('/apt/') ||
        !['GET', 'HEAD'].includes(request.method)) {
      return new Response('Not found', { status: 404 });
    }

    const target = new URL(incoming.pathname + incoming.search, ORIGIN);
    const headers = new Headers();
    for (const name of ['range', 'if-none-match', 'if-modified-since']) {
      const value = request.headers.get(name);
      if (value) headers.set(name, value);
    }
    const response = await fetch(target, {
      method: request.method,
      headers,
      redirect: 'manual',
    });
    const outgoing = new Headers(response.headers);
    outgoing.set('X-Content-Type-Options', 'nosniff');
    return new Response(response.body, {
      status: response.status,
      headers: outgoing,
    });
  },
};
