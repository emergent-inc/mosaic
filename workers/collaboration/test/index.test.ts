import { expect, test } from "bun:test";
import { collaborationFetch, type CollaborationWorkerEnv } from "../src/handler";

class FakeSessionStub {
  createdSessionCode: string | null = null;
  fetchRequests: Request[] = [];
  claimExistingSession = false;

  async create(sessionCode: string) {
    if (this.createdSessionCode !== null || this.claimExistingSession) {
      return {
        metadata: {
          sessionID: this.createdSessionCode ?? sessionCode,
          sessionCode: this.createdSessionCode ?? sessionCode,
        },
        created: false,
      };
    }
    this.createdSessionCode = sessionCode;
    return {
      metadata: {
        sessionID: sessionCode,
        sessionCode,
      },
      created: true,
    };
  }

  async fetch(request: Request) {
    this.fetchRequests.push(request);
    const url = new URL(request.url);
    if (url.pathname === "/metadata") {
      if (this.createdSessionCode === null) {
        return new Response(JSON.stringify({ error: "session_not_found" }), { status: 404 });
      }
      return new Response(JSON.stringify({
        metadata: {
          sessionID: this.createdSessionCode,
          sessionCode: this.createdSessionCode,
        },
      }), {
        headers: { "content-type": "application/json" },
      });
    }
    if (this.createdSessionCode === null) {
      return new Response(JSON.stringify({ error: "session_not_found" }), { status: 404 });
    }
    return new Response("routed-to-session", { status: 299 });
  }
}

class FakeSessionNamespace {
  stubs = new Map<string, FakeSessionStub>();

  idFromName(name: string) {
    return name;
  }

  get(id: string) {
    let stub = this.stubs.get(id);
    if (!stub) {
      stub = new FakeSessionStub();
      this.stubs.set(id, stub);
    }
    return stub;
  }
}

class FakeSessionIndexStub {
  records: Array<Record<string, unknown>> = [];
  requests: Request[] = [];
  failWrites = false;

  async fetch(request: Request) {
    this.requests.push(request);
    const url = new URL(request.url);
    if (url.pathname === "/sessions" && request.method === "POST") {
      if (this.failWrites) throw new Error("index unavailable");
      const record = await request.json() as Record<string, unknown>;
      this.records = [
        record,
        ...this.records.filter((existing) => existing.sessionCode !== record.sessionCode),
      ];
      return new Response(JSON.stringify({ recorded: true }), {
        headers: { "content-type": "application/json" },
      });
    }
    if (url.pathname === "/sessions" && request.method === "GET") {
      return new Response(JSON.stringify({ sessions: this.records, cursor: null }), {
        headers: { "content-type": "application/json" },
      });
    }
    const deleteMatch = url.pathname.match(/^\/sessions\/([^/]+)$/);
    if (deleteMatch && request.method === "DELETE") {
      const sessionCode = decodeURIComponent(deleteMatch[1]).toUpperCase().replace(/[^A-Z0-9]/g, "");
      const beforeCount = this.records.length;
      this.records = this.records.filter((record) => record.sessionCode !== sessionCode);
      return new Response(JSON.stringify({
        deleted: this.records.length !== beforeCount,
        sessionCode,
      }), {
        headers: { "content-type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ error: "not_found" }), { status: 404 });
  }
}

class FakeSessionIndexNamespace {
  stubs = new Map<string, FakeSessionIndexStub>();

  idFromName(name: string) {
    return name;
  }

  get(id: string) {
    let stub = this.stubs.get(id);
    if (!stub) {
      stub = new FakeSessionIndexStub();
      this.stubs.set(id, stub);
    }
    return stub;
  }
}

test("join route uses session code to reach the created session object", async () => {
  const namespace = new FakeSessionNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
  } satisfies CollaborationWorkerEnv;

  const createResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/sessions", { method: "POST" }),
    env
  );
  const created = await createResponse.json() as { sessionCode: string };

  const joinResponse = await collaborationFetch(
    new Request(
      `http://relay.test/v1/collaboration/sessions/${created.sessionCode}/connect`,
      { method: "GET" }
    ),
    env
  );

  const stub = namespace.stubs.get(created.sessionCode);
  expect(createResponse.status).toBe(201);
  expect(joinResponse.status).toBe(299);
  expect(stub?.createdSessionCode).toBe(created.sessionCode);
  expect(stub?.fetchRequests).toHaveLength(1);
  expect(new URL(stub?.fetchRequests[0]?.url ?? "").pathname).toBe(
    `/v1/collaboration/sessions/${created.sessionCode}/connect`
  );
});

test("join route normalizes pasted shareable session codes", async () => {
  const namespace = new FakeSessionNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
  } satisfies CollaborationWorkerEnv;
  namespace.get("5ZNHGF9P").createdSessionCode = "5ZNHGF9P";

  const joinResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/sessions/5znh-gf9p/connect", { method: "GET" }),
    env
  );

  const stub = namespace.stubs.get("5ZNHGF9P");
  expect(joinResponse.status).toBe(299);
  expect(stub?.fetchRequests).toHaveLength(1);
});

test("join route accepts new four-character pasted session codes", async () => {
  const namespace = new FakeSessionNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
  } satisfies CollaborationWorkerEnv;
  namespace.get("5ZNH").createdSessionCode = "5ZNH";

  const joinResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/sessions/5z-nh/connect", { method: "GET" }),
    env
  );

  const stub = namespace.stubs.get("5ZNH");
  expect(joinResponse.status).toBe(299);
  expect(stub?.fetchRequests).toHaveLength(1);
});

test("join route rejects malformed session codes before routing", async () => {
  const namespace = new FakeSessionNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
  } satisfies CollaborationWorkerEnv;

  const joinResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/sessions/abc/connect", { method: "GET" }),
    env
  );
  const body = await joinResponse.json() as { error: string };

  expect(joinResponse.status).toBe(400);
  expect(body.error).toBe("invalid_session_code");
  expect(namespace.stubs.size).toBe(0);
});

test("create route retries when a generated session code is already active", async () => {
  const namespace = new FakeSessionNamespace();
  const indexNamespace = new FakeSessionIndexNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_SESSION_INDEX: indexNamespace,
  } satisfies CollaborationWorkerEnv;
  const originalGetRandomValues = crypto.getRandomValues.bind(crypto);
  let callCount = 0;
  Object.defineProperty(crypto, "getRandomValues", {
    configurable: true,
    value(values: Uint8Array) {
      values.fill(callCount === 0 ? 0 : 1);
      callCount += 1;
      return values;
    },
  });

  try {
    const occupied = namespace.get("00000000");
    occupied.claimExistingSession = true;
    const createResponse = await collaborationFetch(
      new Request("http://relay.test/v1/collaboration/sessions", { method: "POST" }),
      env
    );
    const created = await createResponse.json() as { sessionCode: string };

    expect(createResponse.status).toBe(201);
    expect(created.sessionCode).toBe("11111111");
    expect(namespace.stubs.get("11111111")?.createdSessionCode).toBe("11111111");
    expect(indexNamespace.stubs.get("global")?.records).toEqual([{
      sessionID: "11111111",
      sessionCode: "11111111",
    }]);
  } finally {
    Object.defineProperty(crypto, "getRandomValues", {
      configurable: true,
      value: originalGetRandomValues,
    });
  }
});

test("create route succeeds when optional index recording fails", async () => {
  const namespace = new FakeSessionNamespace();
  const indexNamespace = new FakeSessionIndexNamespace();
  const index = indexNamespace.get("global");
  index.failWrites = true;
  const env = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_SESSION_INDEX: indexNamespace,
  } satisfies CollaborationWorkerEnv;
  const originalWarn = console.warn;
  console.warn = () => {};

  try {
    const createResponse = await collaborationFetch(
      new Request("http://relay.test/v1/collaboration/sessions", { method: "POST" }),
      env
    );
    const created = await createResponse.json() as { sessionCode: string };

    expect(createResponse.status).toBe(201);
    expect(created.sessionCode).toMatch(/^[A-Z0-9]{8}$/);
    expect(index.records).toHaveLength(0);
    expect(index.requests).toHaveLength(1);
  } finally {
    console.warn = originalWarn;
  }
});

test("create route keeps retrying duplicate candidates until a unique code is claimed", async () => {
  const namespace = new FakeSessionNamespace();
  const indexNamespace = new FakeSessionIndexNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_SESSION_INDEX: indexNamespace,
  } satisfies CollaborationWorkerEnv;
  const occupied = namespace.get("00000000");
  occupied.claimExistingSession = true;
  const originalGetRandomValues = crypto.getRandomValues.bind(crypto);
  let callCount = 0;
  Object.defineProperty(crypto, "getRandomValues", {
    configurable: true,
    value(values: Uint8Array) {
      values.fill(callCount < 12 ? 0 : 1);
      callCount += 1;
      return values;
    },
  });

  try {
    const createResponse = await collaborationFetch(
      new Request("http://relay.test/v1/collaboration/sessions", { method: "POST" }),
      env
    );
    const created = await createResponse.json() as { sessionCode: string };

    expect(createResponse.status).toBe(201);
    expect(created.sessionCode).toBe("11111111");
    expect(callCount).toBe(13);
    expect(namespace.stubs.get("11111111")?.createdSessionCode).toBe("11111111");
    expect(indexNamespace.stubs.get("global")?.records).toEqual([{
      sessionID: "11111111",
      sessionCode: "11111111",
    }]);
  } finally {
    Object.defineProperty(crypto, "getRandomValues", {
      configurable: true,
      value: originalGetRandomValues,
    });
  }
});

test("join route reports session_not_found for unknown valid codes", async () => {
  const namespace = new FakeSessionNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
  } satisfies CollaborationWorkerEnv;

  const joinResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/sessions/5znh-gf9p/connect", { method: "GET" }),
    env
  );
  const body = await joinResponse.json() as { error: string };

  expect(joinResponse.status).toBe(404);
  expect(body.error).toBe("session_not_found");
  expect(namespace.stubs.get("5ZNHGF9P")?.fetchRequests).toHaveLength(1);
});

test("admin session index requires a token and lists recorded codes", async () => {
  const namespace = new FakeSessionNamespace();
  const indexNamespace = new FakeSessionIndexNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_SESSION_INDEX: indexNamespace,
    COLLABORATION_ADMIN_TOKEN: "secret",
  } satisfies CollaborationWorkerEnv;

  const createResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/sessions", { method: "POST" }),
    env
  );
  const forbiddenResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/admin/sessions", { method: "GET" }),
    env
  );
  const listResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/admin/sessions", {
      method: "GET",
      headers: { "x-cmux-admin-token": "secret" },
    }),
    env
  );
  const created = await createResponse.json() as { sessionCode: string };
  const body = await listResponse.json() as {
    sessions: Array<{ sessionID: string; sessionCode: string; durableObjectID: string }>;
  };

  expect(createResponse.status).toBe(201);
  expect(forbiddenResponse.status).toBe(403);
  expect(listResponse.status).toBe(200);
  expect(body.sessions).toEqual([{
    sessionID: created.sessionCode,
    sessionCode: created.sessionCode,
    durableObjectID: created.sessionCode,
  }]);
});

test("admin session detail reports active metadata and durable object id", async () => {
  const namespace = new FakeSessionNamespace();
  const indexNamespace = new FakeSessionIndexNamespace();
  namespace.get("NXPLXZAH").createdSessionCode = "NXPLXZAH";
  indexNamespace.get("global").records.push({
    sessionID: "NXPLXZAH",
    sessionCode: "NXPLXZAH",
    createdAt: 1234,
  });
  const env = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_SESSION_INDEX: indexNamespace,
    COLLABORATION_ADMIN_TOKEN: "secret",
  } satisfies CollaborationWorkerEnv;

  const response = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/admin/sessions/nxpl-xzah", {
      method: "GET",
      headers: { "x-cmux-admin-token": "secret" },
    }),
    env
  );
  const body = await response.json() as {
    sessionCode: string;
    durableObjectID: string;
    indexed: boolean;
    active: boolean;
    metadata: { sessionCode: string } | null;
    indexedSession: { sessionCode: string } | null;
  };

  expect(response.status).toBe(200);
  expect(body.sessionCode).toBe("NXPLXZAH");
  expect(body.durableObjectID).toBe("NXPLXZAH");
  expect(body.indexed).toBe(true);
  expect(body.active).toBe(true);
  expect(body.metadata?.sessionCode).toBe("NXPLXZAH");
  expect(body.indexedSession?.sessionCode).toBe("NXPLXZAH");
});

test("admin session detail distinguishes indexed expired codes", async () => {
  const namespace = new FakeSessionNamespace();
  const indexNamespace = new FakeSessionIndexNamespace();
  indexNamespace.get("global").records.push({
    sessionID: "NXPLXZAH",
    sessionCode: "NXPLXZAH",
    createdAt: 1234,
  });
  const env = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_SESSION_INDEX: indexNamespace,
    COLLABORATION_ADMIN_TOKEN: "secret",
  } satisfies CollaborationWorkerEnv;

  const response = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/admin/sessions/NXPLXZAH", {
      method: "GET",
      headers: { "x-cmux-admin-token": "secret" },
    }),
    env
  );
  const body = await response.json() as {
    indexed: boolean;
    active: boolean;
    metadata: unknown;
    indexedSession: { sessionCode: string } | null;
  };

  expect(response.status).toBe(200);
  expect(body.indexed).toBe(true);
  expect(body.active).toBe(false);
  expect(body.metadata).toBeNull();
  expect(body.indexedSession?.sessionCode).toBe("NXPLXZAH");
});

test("admin session detail reports unknown non-indexed codes", async () => {
  const namespace = new FakeSessionNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_SESSION_INDEX: new FakeSessionIndexNamespace(),
    COLLABORATION_ADMIN_TOKEN: "secret",
  } satisfies CollaborationWorkerEnv;

  const response = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/admin/sessions/UNKNOWN1", {
      method: "GET",
      headers: { "x-cmux-admin-token": "secret" },
    }),
    env
  );
  const body = await response.json() as {
    sessionCode: string;
    durableObjectID: string;
    indexed: boolean;
    active: boolean;
  };

  expect(response.status).toBe(200);
  expect(body.sessionCode).toBe("UNKNOWN1");
  expect(body.durableObjectID).toBe("UNKNOWN1");
  expect(body.indexed).toBe(false);
  expect(body.active).toBe(false);
});

test("admin session detail rejects malformed codes before routing", async () => {
  const namespace = new FakeSessionNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_ADMIN_TOKEN: "secret",
  } satisfies CollaborationWorkerEnv;

  const response = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/admin/sessions/abc", {
      method: "GET",
      headers: { "x-cmux-admin-token": "secret" },
    }),
    env
  );
  const body = await response.json() as { error: string };

  expect(response.status).toBe(400);
  expect(body.error).toBe("invalid_session_code");
  expect(namespace.stubs.size).toBe(0);
});

test("admin session index is hidden when disabled or unbound", async () => {
  const namespace = new FakeSessionNamespace();
  const noTokenEnv = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_SESSION_INDEX: new FakeSessionIndexNamespace(),
  } satisfies CollaborationWorkerEnv;
  const noIndexEnv = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_ADMIN_TOKEN: "secret",
  } satisfies CollaborationWorkerEnv;

  const noTokenResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/admin/sessions", {
      method: "GET",
      headers: { "x-cmux-admin-token": "secret" },
    }),
    noTokenEnv
  );
  const noIndexResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/admin/sessions", {
      method: "GET",
      headers: { "x-cmux-admin-token": "secret" },
    }),
    noIndexEnv
  );

  expect(noTokenResponse.status).toBe(404);
  expect(await noTokenResponse.json() as { error: string }).toEqual({ error: "admin_index_disabled" });
  expect(noIndexResponse.status).toBe(404);
  expect(await noIndexResponse.json() as { error: string }).toEqual({ error: "admin_index_disabled" });
});

test("admin session index forwards pagination query parameters", async () => {
  const namespace = new FakeSessionNamespace();
  const indexNamespace = new FakeSessionIndexNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_SESSION_INDEX: indexNamespace,
    COLLABORATION_ADMIN_TOKEN: "secret",
  } satisfies CollaborationWorkerEnv;

  const listResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/admin/sessions?limit=2&cursor=session%3A00000000", {
      method: "GET",
      headers: { "x-cmux-admin-token": "secret" },
    }),
    env
  );

  const requestURL = new URL(indexNamespace.stubs.get("global")?.requests[0]?.url ?? "");
  expect(listResponse.status).toBe(200);
  expect(requestURL.search).toBe("?limit=2&cursor=session%3A00000000");
});

test("deleted index records disappear from admin session list", async () => {
  const namespace = new FakeSessionNamespace();
  const indexNamespace = new FakeSessionIndexNamespace();
  const index = indexNamespace.get("global");
  index.records.push(
    { sessionID: "NXPLXZAH", sessionCode: "NXPLXZAH", createdAt: 2 },
    { sessionID: "JXC62DZN", sessionCode: "JXC62DZN", createdAt: 1 }
  );
  const env = {
    COLLABORATION_SESSIONS: namespace,
    COLLABORATION_SESSION_INDEX: indexNamespace,
    COLLABORATION_ADMIN_TOKEN: "secret",
  } satisfies CollaborationWorkerEnv;

  await index.fetch(new Request("https://cmux-collaboration-index.local/sessions/NXPLXZAH", {
    method: "DELETE",
  }));
  const listResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/admin/sessions", {
      method: "GET",
      headers: { "x-cmux-admin-token": "secret" },
    }),
    env
  );
  const body = await listResponse.json() as {
    sessions: Array<{ sessionCode: string; durableObjectID: string }>;
  };

  expect(listResponse.status).toBe(200);
  expect(body.sessions.map((session) => ({
    sessionCode: session.sessionCode,
    durableObjectID: session.durableObjectID,
  }))).toEqual([{
    sessionCode: "JXC62DZN",
    durableObjectID: "JXC62DZN",
  }]);
});
