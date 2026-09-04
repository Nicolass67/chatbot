export const runtime = "nodejs";

import { runChatOrchestrator } from "@/lib/agent/orchestrator";
import { authenticateRequest } from "@/lib/auth/request-auth";
import { apiErrorResponse } from "@/lib/http/api-error";
import { z } from "zod";

const activeContextSchema = z
  .object({
    fileId: z.string().min(1).optional(),
    mailThreadId: z.string().min(1).optional(),
    rootId: z.string().min(1).optional(),
    label: z.string().max(200).optional(),
  })
  .strict()
  .optional();

const chatSchema = z
  .object({
    conversationId: z.string(),
    message: z.string().max(100000).default(""),
    attachmentIds: z.array(z.string()).max(20).default([]),
    regenerate: z.boolean().optional(),
    editMessageId: z.string().optional(),
    mode: z.enum(["chat", "agent"]).optional(),
    activeContext: activeContextSchema,
  })
  .refine(
    (d) =>
      d.message.trim().length > 0 ||
      d.attachmentIds.length > 0 ||
      Boolean(d.editMessageId),
    {
      message: "Message ou pièce jointe requis",
    }
  );

const SSE_HEADERS = {
  "Content-Type": "text/event-stream",
  "Cache-Control": "no-cache, no-transform",
  "X-Accel-Buffering": "no",
  Connection: "keep-alive",
  "X-Chat-Events-Version": "1",
  "X-API-Version": "1",
} as const;

const HEARTBEAT_INTERVAL_MS = 15_000;

export async function POST(request: Request) {
  const body = chatSchema.parse(await request.json());
  const abortSignal = request.signal;
  const auth = await authenticateRequest(request);
  if (!auth.authenticated || !auth.userId) {
    return apiErrorResponse("AUTH_REQUIRED", "Non autorisé");
  }
  const userId = auth.userId;

  const stream = new ReadableStream({
    async start(controller) {
      const encoder = new TextEncoder();
      let closed = false;
      let heartbeatTimer: ReturnType<typeof setInterval> | undefined;

      const cleanup = () => {
        if (heartbeatTimer) {
          clearInterval(heartbeatTimer);
          heartbeatTimer = undefined;
        }
      };

      const closeStream = () => {
        if (closed) return;
        closed = true;
        cleanup();
        try {
          controller.close();
        } catch {
          // already closed
        }
      };

      const send = (data: unknown) => {
        if (closed || abortSignal.aborted) return;
        try {
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify(data)}\n\n`)
          );
        } catch {
          closeStream();
        }
      };

      heartbeatTimer = setInterval(() => {
        if (closed || abortSignal.aborted) return;
        try {
          controller.enqueue(encoder.encode(`: ping\n\n`));
        } catch {
          closeStream();
        }
      }, HEARTBEAT_INTERVAL_MS);

      const onAbort = () => {
        send({
          type: "error",
          message: "Requête annulée",
          code: "ABORTED",
        });
        closeStream();
      };

      abortSignal.addEventListener("abort", onAbort, { once: true });

      try {
        await runChatOrchestrator({
          conversationId: body.conversationId,
          userContent: body.message,
          userId,
          attachmentIds: body.attachmentIds,
          regenerate: body.regenerate,
          editMessageId: body.editMessageId,
          mode: body.mode,
          activeContext: body.activeContext,
          signal: abortSignal,
          onEvent: (event) => send(event),
        });
      } catch (error) {
        if (!abortSignal.aborted) {
          send({
            type: "error",
            message: error instanceof Error ? error.message : String(error),
          });
        }
      } finally {
        abortSignal.removeEventListener("abort", onAbort);
        closeStream();
      }
    },
    cancel() {
      // Client disconnected — orchestrator abort handled via request.signal
    },
  });

  return new Response(stream, { headers: SSE_HEADERS });
}
