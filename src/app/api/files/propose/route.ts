export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { getDb } from "@/lib/db";
import { conversations } from "@/lib/db/schema";
import { getFilesCapabilities, isFilesFeatureEnabled } from "@/lib/files/feature";
import { createFilesMutationAction } from "@/lib/files/mutations";
import { resolveUnderRoot } from "@/lib/files/path-guard";
import { resolveFileReference } from "@/lib/files/resolve";
import { getFileRoot } from "@/lib/files/roots";
import { eq } from "drizzle-orm";
import { apiErrorResponse } from "@/lib/http/api-error";

const WORKSPACE_CONV_PREFIX = "files-workspace:";

async function ensureWorkspaceConversation(userId: string): Promise<string> {
  const id = `${WORKSPACE_CONV_PREFIX}${userId}`;
  const db = getDb();
  const existing = await db.query.conversations.findFirst({
    where: eq(conversations.id, id),
  });
  if (!existing) {
    await db.insert(conversations).values({
      id,
      title: "Files workspace",
      titleSource: "user",
    });
  }
  return id;
}

function mapWindowsError(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err);
  const lower = msg.toLowerCase();
  if (lower.includes("eexist") || lower.includes("already exists")) {
    return "Un fichier ou dossier portant ce nom existe déjà.";
  }
  if (lower.includes("enoent")) {
    return "Fichier ou dossier introuvable.";
  }
  if (lower.includes("eacces") || lower.includes("eperm")) {
    return "Accès refusé par le système de fichiers.";
  }
  if (lower.includes("ebusy") || lower.includes("locked")) {
    return "Fichier verrouillé ou en cours d’utilisation.";
  }
  if (lower.includes("invalide") || lower.includes("reserved")) {
    return "Nom de fichier invalide sous Windows.";
  }
  return msg;
}

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";
  const caps = getFilesCapabilities();
  const body = (await request.json()) as {
    op?: "create_directory" | "rename_file" | "move_file" | "delete_file";
    sourceFileId?: string;
    destRootId?: string;
    destRelativePath?: string;
    newName?: string;
  };

  try {
    const conversationId = await ensureWorkspaceConversation(userId);

    if (body.op === "create_directory") {
      if (!caps.mkdir) throw new Error("Création de dossier désactivée.");
      if (!body.destRootId || !body.destRelativePath?.trim()) {
        return Response.json({ error: "destRootId et destRelativePath requis" }, { status: 400 });
      }
      const root = await getFileRoot(userId, body.destRootId);
      if (!root?.enabled) throw new Error("Root invalide.");
      const rel = body.destRelativePath.replace(/\\/g, "/");
      resolveUnderRoot(root.absolutePath, rel);
      const proposed = await createFilesMutationAction({
        userId,
        conversationId,
        actionType: "create_directory",
        payload: {
          op: "create_directory",
          destRootId: root.id,
          destRelativePath: rel,
          overwrite: false,
        },
      });
      return Response.json({
        actionId: proposed.actionId,
        confirmationToken: proposed.confirmationToken,
        expiresAt: proposed.expiresAt,
        op: "create_directory",
        payload: {
          destRootId: proposed.payload.destRootId,
          destRelativePath: proposed.payload.destRelativePath,
        },
      });
    }

    if (body.op === "rename_file") {
      if (!caps.rename) throw new Error("Renommage désactivé.");
      if (!body.sourceFileId || !body.newName?.trim()) {
        return Response.json({ error: "sourceFileId et newName requis" }, { status: 400 });
      }
      const newName = body.newName.trim();
      if (newName.includes("/") || newName.includes("\\") || newName === "." || newName === "..") {
        return Response.json({ error: "Nom invalide" }, { status: 400 });
      }
      const resolved = await resolveFileReference(userId, body.sourceFileId);
      if (!resolved.access.canMutate) {
        return Response.json({ error: "Mutation non autorisée" }, { status: 403 });
      }
      const parent = resolved.relativePath.includes("/")
        ? resolved.relativePath.slice(0, resolved.relativePath.lastIndexOf("/"))
        : "";
      const destRelativePath = parent ? `${parent}/${newName}` : newName;
      const proposed = await createFilesMutationAction({
        userId,
        conversationId,
        actionType: "rename_file",
        payload: {
          op: "rename_file",
          sourceFileId: resolved.fileId,
          sourceRootId: resolved.rootId,
          sourceRelativePath: resolved.relativePath,
          destRootId: resolved.rootId,
          destRelativePath,
          expectedSizeBytes: resolved.sizeBytes,
          expectedMtimeMs: resolved.mtimeMs,
          overwrite: false,
        },
      });
      return Response.json({
        actionId: proposed.actionId,
        confirmationToken: proposed.confirmationToken,
        expiresAt: proposed.expiresAt,
        op: "rename_file",
        payload: {
          sourceRelativePath: resolved.relativePath,
          destRootId: resolved.rootId,
          destRelativePath,
        },
      });
    }

    if (body.op === "move_file") {
      if (!caps.move) throw new Error("Déplacement désactivé.");
      if (!body.sourceFileId || !body.destRootId || body.destRelativePath === undefined) {
        return Response.json(
          { error: "sourceFileId, destRootId et destRelativePath requis" },
          { status: 400 }
        );
      }
      const resolved = await resolveFileReference(userId, body.sourceFileId);
      if (!resolved.access.canMutate) {
        return Response.json({ error: "Mutation non autorisée" }, { status: 403 });
      }
      const destRoot = await getFileRoot(userId, body.destRootId);
      if (!destRoot?.enabled) throw new Error("Root destination invalide.");
      const destRel = body.destRelativePath.replace(/\\/g, "/");
      resolveUnderRoot(destRoot.absolutePath, destRel);
      if (
        resolved.rootId === destRoot.id &&
        (destRel === resolved.relativePath ||
          destRel.startsWith(resolved.relativePath + "/"))
      ) {
        return Response.json(
          { error: "Impossible de déplacer un dossier dans lui-même." },
          { status: 400 }
        );
      }
      const proposed = await createFilesMutationAction({
        userId,
        conversationId,
        actionType: "move_file",
        payload: {
          op: "move_file",
          sourceFileId: resolved.fileId,
          sourceRootId: resolved.rootId,
          sourceRelativePath: resolved.relativePath,
          destRootId: destRoot.id,
          destRelativePath: destRel,
          expectedSizeBytes: resolved.sizeBytes,
          expectedMtimeMs: resolved.mtimeMs,
          overwrite: false,
        },
      });
      return Response.json({
        actionId: proposed.actionId,
        confirmationToken: proposed.confirmationToken,
        expiresAt: proposed.expiresAt,
        op: "move_file",
        payload: {
          sourceRelativePath: resolved.relativePath,
          destRootId: destRoot.id,
          destRelativePath: destRel,
        },
      });
    }

    if (body.op === "delete_file") {
      if (!caps.delete) throw new Error("Suppression désactivée.");
      if (!body.sourceFileId) {
        return Response.json({ error: "sourceFileId requis" }, { status: 400 });
      }
      const resolved = await resolveFileReference(userId, body.sourceFileId);
      if (resolved.isDirectory) {
        return Response.json(
          { error: "La suppression de dossiers n’est pas supportée ici." },
          { status: 400 }
        );
      }
      if (!resolved.access.canMutate) {
        return Response.json({ error: "Mutation non autorisée" }, { status: 403 });
      }
      const proposed = await createFilesMutationAction({
        userId,
        conversationId,
        actionType: "delete_file",
        payload: {
          op: "delete_file",
          sourceFileId: resolved.fileId,
          sourceRootId: resolved.rootId,
          sourceRelativePath: resolved.relativePath,
          destRootId: resolved.rootId,
          destRelativePath: resolved.relativePath,
          expectedSizeBytes: resolved.sizeBytes,
          expectedMtimeMs: resolved.mtimeMs,
          overwrite: false,
        },
      });
      return Response.json({
        actionId: proposed.actionId,
        confirmationToken: proposed.confirmationToken,
        expiresAt: proposed.expiresAt,
        op: "delete_file",
        payload: {
          sourceRelativePath: resolved.relativePath,
          destRootId: resolved.rootId,
          destRelativePath: resolved.relativePath,
        },
      });
    }

    return Response.json({ error: "op invalide" }, { status: 400 });
  } catch (err) {
    return Response.json({ error: mapWindowsError(err) }, { status: 400 });
  }
});
