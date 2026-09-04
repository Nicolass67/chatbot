import { z } from "zod";
import { getFilesCapabilities, isFilesFeatureEnabled } from "@/lib/files/feature";
import { requireFilesUserId } from "@/lib/files/helpers";
import { createFilesMutationAction } from "@/lib/files/mutations";
import { resolveFileReference } from "@/lib/files/resolve";
import { getFileRoot } from "@/lib/files/roots";
import { resolveUnderRoot } from "@/lib/files/path-guard";
import type { Tool } from "../types";

const mkdirSchema = z.object({
  rootId: z.string(),
  relativePath: z.string().describe("Chemin relatif sous la root"),
});

const renameSchema = z.object({
  fileId: z.string(),
  newName: z.string().describe("Nouveau nom de fichier (pas un chemin)"),
});

const moveSchema = z.object({
  fileId: z.string(),
  destRootId: z.string(),
  destRelativePath: z.string(),
});

export const fileCreateDirectoryTool: Tool<
  z.infer<typeof mkdirSchema>,
  Record<string, unknown>
> = {
  name: "file_create_directory",
  description:
    "Propose la création d'un dossier (confirmation utilisateur requise). rootId + relativePath.",
  inputSchema: mkdirSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    if (!isFilesFeatureEnabled() || !getFilesCapabilities().mkdir) {
      throw new Error("mkdir désactivé.");
    }
    const userId = requireFilesUserId(ctx);
    const root = await getFileRoot(userId, input.rootId);
    if (!root?.enabled) throw new Error("Root invalide.");
    const rel = input.relativePath.replace(/\\/g, "/");
    resolveUnderRoot(root.absolutePath, rel);

    const proposed = await createFilesMutationAction({
      userId,
      conversationId: ctx.conversationId,
      actionType: "create_directory",
      payload: {
        op: "create_directory",
        destRootId: root.id,
        destRelativePath: rel,
        overwrite: false,
      },
    });

    return {
      status: "pending_confirmation",
      actionId: proposed.actionId,
      confirmationToken: proposed.confirmationToken,
      expiresAt: proposed.expiresAt,
      payload: proposed.payload,
      notice: "Confirmez la création du dossier dans l'interface.",
    };
  },
};

export const fileRenameTool: Tool<
  z.infer<typeof renameSchema>,
  Record<string, unknown>
> = {
  name: "file_rename",
  description:
    "Propose le renommage d'un fichier via fileId (confirmation requise).",
  inputSchema: renameSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    if (!isFilesFeatureEnabled() || !getFilesCapabilities().rename) {
      throw new Error("rename désactivé.");
    }
    const userId = requireFilesUserId(ctx);
    const resolved = await resolveFileReference(userId, input.fileId, {
      requireMutate: true,
    });
    const newName = input.newName.replace(/[\\/]/g, "").trim();
    if (!newName) throw new Error("Nom invalide.");
    const parent = resolved.relativePath.includes("/")
      ? resolved.relativePath.slice(0, resolved.relativePath.lastIndexOf("/"))
      : "";
    const destRelativePath = parent ? `${parent}/${newName}` : newName;

    const proposed = await createFilesMutationAction({
      userId,
      conversationId: ctx.conversationId,
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

    return {
      status: "pending_confirmation",
      actionId: proposed.actionId,
      confirmationToken: proposed.confirmationToken,
      expiresAt: proposed.expiresAt,
      payload: proposed.payload,
      notice: "Confirmez le renommage dans l'interface.",
    };
  },
};

export const fileMoveTool: Tool<
  z.infer<typeof moveSchema>,
  Record<string, unknown>
> = {
  name: "file_move",
  description:
    "Propose le déplacement d'un fichier via fileId (confirmation requise).",
  inputSchema: moveSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    if (!isFilesFeatureEnabled() || !getFilesCapabilities().move) {
      throw new Error("move désactivé.");
    }
    const userId = requireFilesUserId(ctx);
    const resolved = await resolveFileReference(userId, input.fileId, {
      requireMutate: true,
    });
    const destRoot = await getFileRoot(userId, input.destRootId);
    if (!destRoot?.enabled) throw new Error("Root destination invalide.");
    const destRel = input.destRelativePath.replace(/\\/g, "/");
    resolveUnderRoot(destRoot.absolutePath, destRel);

    const proposed = await createFilesMutationAction({
      userId,
      conversationId: ctx.conversationId,
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

    return {
      status: "pending_confirmation",
      actionId: proposed.actionId,
      confirmationToken: proposed.confirmationToken,
      expiresAt: proposed.expiresAt,
      payload: proposed.payload,
      notice: "Confirmez le déplacement dans l'interface.",
    };
  },
};
