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

  const joinResponse = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/sessions/5z-nh/connect", { method: "GET" }),
    env
  );

  const stub = namespace.stubs.get("5ZNH");
  expect(joinResponse.status).toBe(299);
  expect(stub?.fetchRequests).toHaveLength(1);
});

test("create route retries when a generated session code is already active", async () => {
  const namespace = new FakeSessionNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
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
    const occupied = namespace.get("AAAA");
    occupied.claimExistingSession = true;
    const createResponse = await collaborationFetch(
      new Request("http://relay.test/v1/collaboration/sessions", { method: "POST" }),
      env
    );
    const created = await createResponse.json() as { sessionCode: string };

    expect(createResponse.status).toBe(201);
    expect(created.sessionCode).toBe("BBBB");
    expect(namespace.stubs.get("BBBB")?.createdSessionCode).toBe("BBBB");
  } finally {
    Object.defineProperty(crypto, "getRandomValues", {
      configurable: true,
      value: originalGetRandomValues,
    });
  }
});

test("create route reports exhaustion when every generated code is already active", async () => {
  const namespace = new FakeSessionNamespace();
  const env = {
    COLLABORATION_SESSIONS: namespace,
  } satisfies CollaborationWorkerEnv;
  const occupied = namespace.get("AAAA");
  occupied.claimExistingSession = true;
  const originalGetRandomValues = crypto.getRandomValues.bind(crypto);
  let callCount = 0;
  Object.defineProperty(crypto, "getRandomValues", {
    configurable: true,
    value(values: Uint8Array) {
      values.fill(0);
      callCount += 1;
      return values;
    },
  });

  try {
    const createResponse = await collaborationFetch(
      new Request("http://relay.test/v1/collaboration/sessions", { method: "POST" }),
      env
    );
    const body = await createResponse.json() as { error: string };

    expect(createResponse.status).toBe(503);
    expect(body.error).toBe("session_code_exhausted");
    expect(callCount).toBe(8);
  } finally {
    Object.defineProperty(crypto, "getRandomValues", {
      configurable: true,
      value: originalGetRandomValues,
    });
  }
});
