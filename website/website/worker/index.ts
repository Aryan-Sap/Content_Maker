/** Cloudflare Worker entry point for the vinext-starter template. */
import { handleImageOptimization, DEFAULT_DEVICE_SIZES, DEFAULT_IMAGE_SIZES } from "vinext/server/image-optimization";
import handler from "vinext/server/app-router-entry";

interface Env {
  ASSETS: Fetcher;
  DB: D1Database;
  DOWNLOADS: R2Bucket;
  RELEASE_UPLOAD_TOKEN: string;
  IMAGES: {
    input(stream: ReadableStream): {
      transform(options: Record<string, unknown>): {
        output(options: { format: string; quality: number }): Promise<{ response(): Response }>;
      };
    };
  };
}

const WINDOWS_DOWNLOAD_PATH = "/downloads/ContentMakerSetup.exe";
const WINDOWS_DOWNLOAD_KEY = "releases/ContentMakerSetup.exe";
const LEGACY_WINDOWS_DOWNLOAD_KEY = "releases/ContentMaker-windows-x64.zip";

function isReleaseUploader(request: Request, env: Env): boolean {
  const expected = env.RELEASE_UPLOAD_TOKEN;
  return Boolean(expected) && request.headers.get("authorization") === `Bearer ${expected}`;
}

async function handleWindowsDownload(request: Request, env: Env): Promise<Response> {
  const object = await env.DOWNLOADS.get(WINDOWS_DOWNLOAD_KEY);
  if (!object) {
    return new Response("The Windows release is being prepared. Please try again shortly.", {
      status: 404,
    });
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("content-type", "application/vnd.microsoft.portable-executable");
  headers.set(
    "content-disposition",
    'attachment; filename="ContentMakerSetup.exe"',
  );
  headers.set("content-length", String(object.size));
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "public, max-age=300");

  return new Response(request.method === "HEAD" ? null : object.body, { headers });
}

async function handleReleaseUpload(request: Request, env: Env): Promise<Response> {
  if (!isReleaseUploader(request, env)) {
    return new Response("Not found", { status: 404 });
  }

  const url = new URL(request.url);
  const prefix = "/api/releases/windows/multipart";
  const suffix = url.pathname.slice(prefix.length).replace(/^\//, "");
  const segments = suffix ? suffix.split("/") : [];

  if (request.method === "POST" && segments.length === 0) {
    const upload = await env.DOWNLOADS.createMultipartUpload(WINDOWS_DOWNLOAD_KEY, {
      httpMetadata: {
        contentType: "application/vnd.microsoft.portable-executable",
        contentDisposition: 'attachment; filename="ContentMakerSetup.exe"',
      },
      customMetadata: {
        version: "1.1.0",
        platform: "windows-x64",
        package: "installer",
      },
    });
    return Response.json({ uploadId: upload.uploadId, key: upload.key });
  }

  const uploadId = segments[0];
  if (!uploadId) {
    return new Response("Invalid upload", { status: 400 });
  }

  const upload = env.DOWNLOADS.resumeMultipartUpload(WINDOWS_DOWNLOAD_KEY, uploadId);

  if (request.method === "PUT" && segments.length === 2) {
    const partNumber = Number.parseInt(segments[1], 10);
    if (!Number.isInteger(partNumber) || partNumber < 1 || !request.body) {
      return new Response("Invalid upload part", { status: 400 });
    }
    const part = await upload.uploadPart(partNumber, request.body);
    return Response.json(part);
  }

  if (request.method === "POST" && segments[1] === "complete") {
    const payload = (await request.json()) as {
      parts?: Array<{ partNumber: number; etag: string }>;
    };
    if (!payload.parts?.length) {
      return new Response("Missing upload parts", { status: 400 });
    }
    const object = await upload.complete(payload.parts);
    await env.DOWNLOADS.delete(LEGACY_WINDOWS_DOWNLOAD_KEY);
    return Response.json({ key: object.key, size: object.size, etag: object.etag });
  }

  if (request.method === "DELETE" && segments[1] === "abort") {
    await upload.abort();
    return new Response(null, { status: 204 });
  }

  return new Response("Not found", { status: 404 });
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

// Image security config. SVG sources with .svg extension auto-skip the
// optimization endpoint on the client side (served directly, no proxy).
// To route SVGs through the optimizer (with security headers), set
// dangerouslyAllowSVG: true in next.config.js and uncomment below:
// const imageConfig: ImageConfig = { dangerouslyAllowSVG: true };

const worker = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (
      url.pathname === WINDOWS_DOWNLOAD_PATH &&
      (request.method === "GET" || request.method === "HEAD")
    ) {
      return handleWindowsDownload(request, env);
    }

    if (url.pathname.startsWith("/api/releases/windows/multipart")) {
      return handleReleaseUpload(request, env);
    }

    if (url.pathname === "/_vinext/image") {
      const allowedWidths = [...DEFAULT_DEVICE_SIZES, ...DEFAULT_IMAGE_SIZES];
      return handleImageOptimization(request, {
        fetchAsset: (path) => env.ASSETS.fetch(new Request(new URL(path, request.url))),
        transformImage: async (body, { width, format, quality }) => {
          const result = await env.IMAGES.input(body).transform(width > 0 ? { width } : {}).output({ format, quality });
          return result.response();
        },
      }, allowedWidths);
    }

    return handler.fetch(request, env, ctx);
  },
};

export default worker;
