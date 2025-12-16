import { ServerSentEventGenerator } from "@starfederation/datastar-sdk/web";

import indexHTML from "./index.html" with { type: "text" };

const server = Bun.serve({
  port: 8092,
  routes: {
    "/": () => {
      return new Response(
        indexHTML,
        {
          headers: { "Content-Type": "text/html" },
        },
      );
    },
  },
});

console.log("TS Server is running on http://localhost:" + server.port);
