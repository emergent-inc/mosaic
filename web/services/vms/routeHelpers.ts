import type { Span } from "@opentelemetry/api";
import { recordSpanError, withApiRouteSpan, type MaybeAttributes } from "../telemetry";
import { unauthorized, verifyRequest, type AuthedUser } from "./auth";
import {
  isVmBillingError,
  isVmDatabaseError,
  isVmProviderOperationError,
} from "./errors";
import { recordSpanTiming } from "./timings";

/** Native bearer token the mac app stashes in keychain. */
export type NativeBearer = { accessToken: string };

export function parseBearer(request: Request): NativeBearer | null {
  const auth = request.headers.get("authorization");
  if (!auth?.toLowerCase().startsWith("bearer ")) return null;
  const accessToken = auth.slice("bearer ".length).trim();
  if (!accessToken) return null;
  return { accessToken };
}

export type AuthedVmRouteContext = {
  user: AuthedUser;
  span: Span;
  authDurationMs: number;
  routeStartedAtMs: number;
  setResponseFinalizer: (finalizer: ((response: Response) => void) | null) => void;
};

export async function withAuthedVmApiRoute(
  request: Request,
  route: string,
  attributes: MaybeAttributes,
  failureLog: string,
  handler: (context: AuthedVmRouteContext) => Promise<Response>,
): Promise<Response> {
  return withApiRouteSpan(
    request,
    route,
    { "mosaic.subsystem": "vm-cloud", ...attributes },
    async (span) => {
      let responseFinalizer: ((response: Response) => void) | null = null;
      const setResponseFinalizer = (finalizer: ((response: Response) => void) | null) => {
        responseFinalizer = finalizer;
      };
      const finalize = (response: Response): Response => {
        if (!responseFinalizer) return response;
        try {
          responseFinalizer(response);
        } catch (err) {
          recordSpanError(span, err);
          console.error(`${failureLog}: response finalizer failed`, err);
        }
        return response;
      };

      try {
        const routeStartedAtMs = performance.now();
        const bearer = parseBearer(request);
        const authStart = performance.now();
        const user = await verifyRequest(request, { requestedTeamId: requestedVmTeamIdFromRequest(request) });
        const authDurationMs = performance.now() - authStart;
        recordSpanTiming(span, "auth", authDurationMs);
        if (!user) return unauthorized();
        if (requiresBrowserMutationProtection(request.method, bearer) && !browserMutationOriginAllowed(request)) {
          return jsonResponse({ error: "forbidden" }, 403);
        }
        return finalize(await handler({ user, span, authDurationMs, routeStartedAtMs, setResponseFinalizer }));
      } catch (err) {
        recordSpanError(span, err);
        console.error(failureLog, err);
        const workflowError = vmWorkflowErrorResponse(err);
        if (workflowError) return finalize(workflowError);
        return finalize(vmErrorResponse({
          error: "vm_internal_error",
          status: 500,
          message: "Cloud VM request failed unexpectedly.",
          action: "Try again. If it keeps failing, copy this error and contact support so we can inspect the server logs.",
          details: { route },
        }));
      }
    },
  );
}

/**
 * `Response.json(...)` misbehaves under Next.js 16's turbopack dev build (the handler's
 * promise settles but turbopack reports "No response is returned from route handler").
 * Use `new Response(JSON.stringify(...), { ... })` explicitly instead.
 */
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export type VmErrorResponseInput = {
  readonly error: string;
  readonly message: string;
  readonly action: string;
  readonly status: number;
  readonly reason?: string;
  readonly extra?: Record<string, unknown>;
  readonly details?: Record<string, unknown>;
};

export function vmErrorResponse(input: VmErrorResponseInput): Response {
  return jsonResponse({
    ...(input.extra ?? {}),
    ...(input.details ? { details: input.details } : {}),
    error: input.error,
    message: input.message,
    reason: input.reason ?? input.message,
    action: input.action,
  }, input.status);
}

export function notFoundVm(vmId: string): Response {
  return vmErrorResponse({
    error: "vm_not_found",
    status: 404,
    message: `Cloud VM ${vmId} was not found.`,
    action: "Run `mosaic vm ls` to see available Cloud VMs. If the VM stopped while idle, start a new one with `mosaic vm new`.",
    details: { vmId },
  });
}

export function vmWorkflowErrorResponse(err: unknown): Response | null {
  if (isVmProviderOperationError(err)) {
    return vmErrorResponse({
      error: "vm_cloud_service_unavailable",
      status: 502,
      message: "The Cloud VM service could not complete this request.",
      action: cloudServiceAction(err.operation),
      details: { operation: err.operation },
    });
  }

  if (isVmDatabaseError(err)) {
    return vmErrorResponse({
      error: "vm_cloud_state_unavailable",
      status: 503,
      message: "Cloud VM state is temporarily unavailable.",
      action: "Retry in a minute. If this keeps happening, contact support so we can check Cloud VM state for your account.",
      details: { operation: err.operation },
    });
  }

  if (isVmBillingError(err)) {
    return vmErrorResponse({
      error: "vm_billing_unavailable",
      status: 503,
      message: "Cloud VM billing could not be checked right now.",
      action: "Retry in a minute. If the problem persists, ask an admin to check this team's Cloud VM billing setup.",
      details: { operation: err.operation },
    });
  }

  return null;
}

function cloudServiceAction(operation: string): string {
  switch (operation) {
    case "create":
      return "Retry once. If it fails again, run `mosaic vm ls` to check whether a VM was created, then try `mosaic vm new` again or contact support.";
    case "openAttach":
    case "openSSH":
      return "Run `mosaic vm ls` to confirm the VM still exists. If it was paused or destroyed, start a fresh VM with `mosaic vm new`.";
    case "exec":
      return "Check that the VM is still running with `mosaic vm ls`, then retry the command. For long commands, increase the exec timeout.";
    case "destroy":
      return "Run `mosaic vm ls` to see whether the VM is already gone. If it still appears, retry `mosaic vm rm <id>`.";
    default:
      return "Retry the command. If it keeps failing, copy this error and contact support.";
  }
}

export function requestedVmTeamIdFromRequest(request: Request): string | null {
  const fromHeader = normalizedOptionalString(
    request.headers.get("x-mosaic-team-id") ??
      request.headers.get("x-mosaic-billing-team-id"),
  );
  if (fromHeader) return fromHeader;

  let url: URL;
  try {
    url = new URL(request.url);
  } catch {
    return null;
  }

  return normalizedOptionalString(
    url.searchParams.get("teamId") ??
      url.searchParams.get("team_id") ??
      url.searchParams.get("billingTeamId") ??
      url.searchParams.get("billing_team_id"),
  );
}

function requiresBrowserMutationProtection(method: string, bearer: NativeBearer | null): boolean {
  if (!["POST", "PUT", "PATCH", "DELETE"].includes(method.toUpperCase())) {
    return false;
  }
  return bearer === null;
}

function browserMutationOriginAllowed(request: Request): boolean {
  const origin = request.headers.get("origin")?.trim();
  const secFetchSite = request.headers.get("sec-fetch-site")?.trim().toLowerCase();

  if (secFetchSite === "cross-site") return false;
  if (!origin) return false;

  const requestOrigin = requestURLOrigin(request);
  if (requestOrigin && origin === requestOrigin) return true;
  return allowedBrowserOrigins().has(origin);
}

function requestURLOrigin(request: Request): string | null {
  try {
    return new URL(request.url).origin;
  } catch {
    return null;
  }
}

let cachedAllowedOriginsEnv: string | undefined;
let cachedAllowedOrigins: Set<string> | null = null;

// MOSAIC_VM_ALLOWED_ORIGINS is a comma-separated list of full origins that must match
// the Origin header exactly, for example `https://app.example.com,https://staging.example.com`.
// Do not include paths, schemeless hosts, or trailing slashes.
function allowedBrowserOrigins(): Set<string> {
  const raw = process.env.MOSAIC_VM_ALLOWED_ORIGINS;
  if (cachedAllowedOrigins && cachedAllowedOriginsEnv === raw) return cachedAllowedOrigins;
  cachedAllowedOriginsEnv = raw;
  const configured = raw?.split(",") ?? [];
  cachedAllowedOrigins = new Set(
    configured
      .map((origin) => origin.trim())
      .filter((origin) => origin.length > 0),
  );
  return cachedAllowedOrigins;
}

function normalizedOptionalString(value: string | null | undefined): string | null {
  const normalized = value?.trim();
  return normalized ? normalized : null;
}
