export async function onRequestPost({ request }) {
  const proxied = new Request("https://api.openpanel.dev/track", request);
  proxied.headers.set("openpanel-client-ip", request.headers.get("cf-connecting-ip") ?? "");
  proxied.headers.delete("cookie");
  return fetch(proxied);
}
