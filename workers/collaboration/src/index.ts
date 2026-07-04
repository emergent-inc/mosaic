import { CollaborationSessionObject } from "./session";
import { CollaborationSessionIndexObject } from "./session-index";
import { collaborationFetch } from "./handler";

export { CollaborationSessionIndexObject, CollaborationSessionObject };

export interface Env {
  COLLABORATION_SESSIONS: DurableObjectNamespace<CollaborationSessionObject>;
  COLLABORATION_SESSION_INDEX: DurableObjectNamespace<CollaborationSessionIndexObject>;
  COLLABORATION_ADMIN_TOKEN?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return collaborationFetch(request, env);
  },
} satisfies ExportedHandler<Env>;
