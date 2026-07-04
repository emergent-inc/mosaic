import { expect, test } from "bun:test";
import { collaborationFetch, type CollaborationWorkerEnv } from "../src/handler";
import {
  CollaborationInboxState,
  INBOX_HEARTBEAT_TYPE,
  INBOX_NUDGE_TYPE,
} from "../src/inbox-state";

class FakeInboxStub {
  requests: Request[] = [];
  delivered = 0;

  async fetch(request: Request) {
    this.requests.push(request);
    const url = new URL(request.url);
    if (url.pathname === "/notify" && request.method === "POST") {
      return new Response(JSON.stringify({ delivered: this.delivered }), {
        headers: { "content-type": "application/json" },
      });
    }
    if (url.pathname.endsWith("/connect")) {
      return new Response("routed-to-inbox", { status: 299 });
    }
    return new Response(JSON.stringify({ error: "not_found" }), { status: 404 });
  }
}

class FakeInboxNamespace {
  stubs = new Map<string, FakeInboxStub>();

  idFromName(name: string) {
    return name;
  }

  get(id: string) {
    let stub = this.stubs.get(id);
    if (!stub) {
      stub = new FakeInboxStub();
      this.stubs.set(id, stub);
    }
    return stub;
  }
}

class FakeSessionNamespace {
  idFromName(name: string) {
    return name;
  }
  get() {
    throw new Error("session namespace should not be used by inbox routes");
  }
}

function inboxEnv(inbox: FakeInboxNamespace): CollaborationWorkerEnv {
  return {
    COLLABORATION_SESSIONS: new FakeSessionNamespace() as never,
    COLLABORATION_INBOX: inbox,
  };
}

test("notify route fans a nudge to the invitee's inbox object", async () => {
  const inbox = new FakeInboxNamespace();
  inbox.get("user-42").delivered = 2;

  const response = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/inbox/notify", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ inviteeUserId: "user-42" }),
    }),
    inboxEnv(inbox),
  );
  const body = (await response.json()) as { delivered: number };

  expect(response.status).toBe(202);
  expect(body.delivered).toBe(2);
  const stub = inbox.stubs.get("user-42");
  expect(stub?.requests).toHaveLength(1);
  expect(new URL(stub?.requests[0]?.url ?? "").pathname).toBe("/notify");
});

test("notify route rejects a missing invitee id", async () => {
  const inbox = new FakeInboxNamespace();

  const response = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/inbox/notify", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ inviteeUserId: "   " }),
    }),
    inboxEnv(inbox),
  );
  const body = (await response.json()) as { error: string };

  expect(response.status).toBe(400);
  expect(body.error).toBe("invalid_user");
  expect(inbox.stubs.size).toBe(0);
});

test("notify route reports inbox_disabled without a binding", async () => {
  const response = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/inbox/notify", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ inviteeUserId: "user-1" }),
    }),
    { COLLABORATION_SESSIONS: new FakeSessionNamespace() as never },
  );
  const body = (await response.json()) as { error: string };

  expect(response.status).toBe(404);
  expect(body.error).toBe("inbox_disabled");
});

test("connect route routes to the user's inbox object", async () => {
  const inbox = new FakeInboxNamespace();

  const response = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/inbox/connect?userID=user-9", {
      method: "GET",
      headers: { upgrade: "websocket" },
    }),
    inboxEnv(inbox),
  );

  expect(response.status).toBe(299);
  expect(inbox.stubs.get("user-9")?.requests).toHaveLength(1);
});

test("connect route rejects a missing user id", async () => {
  const inbox = new FakeInboxNamespace();

  const response = await collaborationFetch(
    new Request("http://relay.test/v1/collaboration/inbox/connect", {
      method: "GET",
      headers: { upgrade: "websocket" },
    }),
    inboxEnv(inbox),
  );
  const body = (await response.json()) as { error: string };

  expect(response.status).toBe(400);
  expect(body.error).toBe("invalid_user");
  expect(inbox.stubs.size).toBe(0);
});

class FakeInboxSocket {
  sent: string[] = [];
  closed: { code: number; reason: string } | null = null;

  send(data: string): void {
    this.sent.push(data);
  }

  close(code: number, reason: string): void {
    this.closed = { code, reason };
  }
}

test("inbox state nudges a freshly connected socket", () => {
  const state = new CollaborationInboxState();
  const socket = new FakeInboxSocket();

  state.addConnection("c1", socket, 1_000);

  expect(state.connectionCount).toBe(1);
  expect(socket.sent).toHaveLength(1);
  expect(JSON.parse(socket.sent[0]!).type).toBe(INBOX_NUDGE_TYPE);
});

test("inbox state fans a notify to every live connection", () => {
  const state = new CollaborationInboxState();
  const first = new FakeInboxSocket();
  const second = new FakeInboxSocket();
  state.addConnection("c1", first, 1_000);
  state.addConnection("c2", second, 1_000);

  const delivered = state.notify("invite", 2_000);

  expect(delivered).toBe(2);
  expect(JSON.parse(first.sent.at(-1)!).type).toBe(INBOX_NUDGE_TYPE);
  expect(JSON.parse(second.sent.at(-1)!).type).toBe(INBOX_NUDGE_TYPE);
});

test("inbox state keeps heartbeating connections alive but expires stale ones", () => {
  const state = new CollaborationInboxState();
  const socket = new FakeInboxSocket();
  state.addConnection("c1", socket, 0);

  state.handleMessage("c1", JSON.stringify({ type: INBOX_HEARTBEAT_TYPE }), 50_000);
  state.expire(60_000, 60_000);
  expect(state.connectionCount).toBe(1);

  state.expire(200_000, 60_000);
  expect(state.connectionCount).toBe(0);
  expect(socket.closed?.code).toBe(1001);
});

test("inbox state drops a connection that sends an invalid frame", () => {
  const state = new CollaborationInboxState();
  const socket = new FakeInboxSocket();
  state.addConnection("c1", socket, 0);

  state.handleMessage("c1", "not-json", 1_000);

  expect(state.connectionCount).toBe(0);
  expect(socket.closed?.code).toBe(1003);
});
