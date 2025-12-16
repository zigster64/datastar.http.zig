import { ServerSentEventGenerator } from "@starfederation/datastar-sdk/web";

import indexHTML from "./index.html" with { type: "text" };
import sseHTML from "./sse.html" with { type: "text" };

const server = Bun.serve({
  port: 8092,
  routes: {
    "/": () => {
      const start = Bun.nanoseconds();

      const res = new Response(
        indexHTML,
        {
          headers: { "Content-Type": "text/html" },
        },
      );

      const duration = (Bun.nanoseconds() - start) / 1000;
      console.log(`TS index handler took ${duration.toFixed(0)} microseconds`);
      return res;
    },
    "/sse": () => {
      const start = Bun.nanoseconds();

      // This creates the Response object and initializes the stream
      const res = ServerSentEventGenerator.stream((stream) => {
        stream.patchElements(sseHTML);
      });

      const duration = (Bun.nanoseconds() - start) / 1000;
      console.log(`TS SSE handler took ${duration.toFixed(0)} microseconds`);
      return res;
    }
  },
});

console.log("TS Server is running on http://localhost:" + server.port);
