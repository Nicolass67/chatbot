import { z } from "zod";

/** Trois axes de contrôle — représentés en types, pas seulement en doc. */
export type FileAccessAxes = {
  canAccessPath: boolean;
  canExposeToLlm: boolean;
  canMutate: boolean;
};

export type FileAccessReasonCode =
  | "OK"
  | "ROOT_DENIED"
  | "PATH_ESCAPE"
  | "REPARSE_REJECTED"
  | "UNC_REJECTED"
  | "ADS_REJECTED"
  | "SENSITIVE_PATTERN"
  | "CAPABILITY_DISABLED"
  | "FEATURE_DISABLED"
  | "NO_ROOTS"
  | "NOT_FOUND"
  | "STALE_REFERENCE"
  | "FORBIDDEN_USER"
  | "TOO_LARGE"
  | "UNSUPPORTED_FORMAT";

export type FileAccessDecision = FileAccessAxes & {
  reasonCodes: FileAccessReasonCode[];
};

export type FilesCapabilities = {
  search: boolean;
  read: boolean;
  analyze: boolean;
  mkdir: boolean;
  rename: boolean;
  move: boolean;
};

export const DEFAULT_FILES_CAPABILITIES: FilesCapabilities = {
  search: true,
  read: true,
  analyze: true,
  mkdir: true,
  rename: true,
  move: true,
};

export const filesCapabilitiesSchema = z.object({
  search: z.boolean().default(true),
  read: z.boolean().default(true),
  analyze: z.boolean().default(true),
  mkdir: z.boolean().default(true),
  rename: z.boolean().default(true),
  move: z.boolean().default(true),
});

export type FileRootRecord = {
  id: string;
  userId: string;
  label: string;
  absolutePath: string;
  enabled: boolean;
  isDefault: boolean;
  createdAt: string;
};

export type FileReferenceRecord = {
  id: string;
  userId: string;
  rootId: string;
  relativePath: string;
  displayName: string;
  sizeBytes: number;
  mtimeMs: number;
  createdAt: string;
  expiresAt: string;
};

export type ResolvedFile = {
  fileId: string;
  rootId: string;
  relativePath: string;
  absolutePath: string;
  displayName: string;
  sizeBytes: number;
  mtimeMs: number;
  isDirectory: boolean;
  access: FileAccessDecision;
};

export type FileSearchHit = {
  fileId: string;
  filename: string;
  relativePath: string;
  rootId: string;
  sizeBytes: number;
  mtimeMs: number;
  extension: string;
  score: number;
  snippet?: string;
};

export type FileListEntry = {
  fileId: string;
  name: string;
  relativePath: string;
  isDirectory: boolean;
  sizeBytes: number;
  mtimeMs: number;
  indexed?: boolean;
};

export type FileStatResult = {
  fileId: string;
  name: string;
  relativePath: string;
  rootId: string;
  isDirectory: boolean;
  sizeBytes: number;
  mtimeMs: number;
  extension: string;
  access: FileAccessAxes;
};

export type FilesMutationOp = "create_directory" | "rename_file" | "move_file";

export type FrozenFilesMutationPayload = {
  op: FilesMutationOp;
  sourceFileId?: string;
  sourceRootId?: string;
  sourceRelativePath?: string;
  destRootId: string;
  destRelativePath: string;
  expectedSizeBytes?: number;
  expectedMtimeMs?: number;
  overwrite: false;
};

export class FilesError extends Error {
  readonly code: FileAccessReasonCode | "INTERNAL" | "POLICY";

  constructor(
    code: FileAccessReasonCode | "INTERNAL" | "POLICY",
    message: string
  ) {
    super(message);
    this.name = "FilesError";
    this.code = code;
  }
}
