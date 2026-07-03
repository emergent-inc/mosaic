const r2PublicBaseURL = process.env.MOSAIC_R2_PUBLIC_BASE_URL?.trim();

function releaseAssetURL(path: string): URL | null {
  if (!r2PublicBaseURL) return null;
  const base = r2PublicBaseURL.endsWith("/") ? r2PublicBaseURL : `${r2PublicBaseURL}/`;
  return new URL(path.replace(/^\/+/, ""), base);
}

export function redirectToReleaseAsset(path: string): Response {
  const url = releaseAssetURL(path);
  if (!url) {
    return new Response("MOSAIC_R2_PUBLIC_BASE_URL is not configured", {
      status: 503,
      headers: { "cache-control": "no-store" },
    });
  }
  return Response.redirect(url, 302);
}

export async function proxyAppcast(path: string): Promise<Response> {
  const url = releaseAssetURL(path);
  if (!url) {
    return new Response("MOSAIC_R2_PUBLIC_BASE_URL is not configured", {
      status: 503,
      headers: { "cache-control": "no-store" },
    });
  }

  const upstream = await fetch(url, { cache: "no-store" });
  if (!upstream.ok) {
    return new Response("Appcast is not available", {
      status: upstream.status,
      headers: { "cache-control": "no-store" },
    });
  }

  return new Response(await upstream.arrayBuffer(), {
    status: 200,
    headers: {
      "content-type": upstream.headers.get("content-type") ?? "application/xml; charset=utf-8",
      "cache-control": "no-cache, no-store, must-revalidate",
    },
  });
}
