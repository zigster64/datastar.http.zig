import { serve } from "bun";
// 1. Import embed equivalent (requires exact filename match)
import indexHTML from "./index.html" with { type: "text" };

const PORT = 8092;

serve({
  port: PORT,
  async fetch(req) {
    const start = Bun.nanoseconds();

    // 2. Prepare the SSE event
    // Datastar expects: event: datastar-merge-fragments
    const eventName = "datastar-merge-fragments";

    // SSE spec requires every line of data to be prefixed with "data: "
    const dataBlock = indexHTML
      .split("\n")
      .map((line) => `data: ${line}`)
      .join("\n");

    const ssePayload = `event: ${eventName}\n${dataBlock}\n\n`;

    // 3. Log duration (Bun.nanoseconds returns nanos, convert to micros)
    const duration = (Bun.nanoseconds() - start) / 1000;
    console.log(`Bun handler took ${duration.toFixed(0)} microseconds`);

    // 4. Return the SSE stream
    return new Response(ssePayload, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
      },
    });
  },
});

console.log(`Bun Datastar SSE Server running at http://localhost:${PORT}`);
