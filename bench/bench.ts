import { ServerSentEventGenerator } from "@starfederation/datastar-sdk/web";

import indexHTML from "./index.html" with { type: "text" };
import sseHTML from "./sse.html" with { type: "text" };

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
    "/log": () => {
      const start = Bun.nanoseconds();

      const res = new Response(
        indexHTML,
        {
          headers: { "Content-Type": "text/html" },
        },
      );

      console.log('TS index handler took', Bun.nanoseconds() - start, "ns");
      return res;
    },
    "/sse": () => {
      const start = Bun.nanoseconds();

      // This creates the Response object and initializes the stream
      const res = ServerSentEventGenerator.stream((stream) => {
        stream.patchElements(indexHTML);
      });

      console.log('TS SSE handler took', Bun.nanoseconds() - start, 'ns');
      return res;
    }
  },
});

console.log("TS Server is running on http://localhost:" + server.port);
