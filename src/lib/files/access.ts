import path from "node:path";
import {
  SENSITIVE_NAME_PATTERNS,
  SENSITIVE_PATH_SEGMENT_PATTERNS,
} from "./constants";
import type { FileAccessDecision, FileAccessReasonCode } from "./types";

function deny(
  codes: FileAccessReasonCode[],
  partial?: Partial<FileAccessDecision>
): FileAccessDecision {
  return {
    canAccessPath: false,
    canExposeToLlm: false,
    canMutate: false,
    reasonCodes: codes,
    ...partial,
  };
}

export function isSensitiveRelativePath(relativePath: string): boolean {
  const normalized = relativePath.replace(/\\/g, "/");
  const base = path.posix.basename(normalized);
  if (SENSITIVE_NAME_PATTERNS.some((re) => re.test(base))) return true;
  if (SENSITIVE_PATH_SEGMENT_PATTERNS.some((re) => re.test(normalized))) {
    return true;
  }
  return false;
}

/**
 * Classifie un chemin relatif déjà contenu dans une root allowlistée.
 * CAN_ACCESS_PATH peut être true tout en refusant EXPOSE / MUTATE.
 */
export function classifyRelativePathAccess(
  relativePath: string,
  options?: { featureEnabled?: boolean; rootOk?: boolean }
): FileAccessDecision {
  if (options?.featureEnabled === false) {
    return deny(["FEATURE_DISABLED"]);
  }
  if (options?.rootOk === false) {
    return deny(["ROOT_DENIED"]);
  }

  if (isSensitiveRelativePath(relativePath)) {
    return {
      canAccessPath: true,
      canExposeToLlm: false,
      canMutate: false,
      reasonCodes: ["SENSITIVE_PATTERN"],
    };
  }

  return {
    canAccessPath: true,
    canExposeToLlm: true,
    canMutate: true,
    reasonCodes: ["OK"],
  };
}

export function requireExposeToLlm(access: FileAccessDecision): void {
  if (!access.canAccessPath) {
    throw new Error(`Accès chemin refusé (${access.reasonCodes.join(",")}).`);
  }
  if (!access.canExposeToLlm) {
    throw new Error(
      `Contenu non exposable au LLM (${access.reasonCodes.join(",")}).`
    );
  }
}

export function requireMutate(access: FileAccessDecision): void {
  if (!access.canAccessPath) {
    throw new Error(`Accès chemin refusé (${access.reasonCodes.join(",")}).`);
  }
  if (!access.canMutate) {
    throw new Error(
      `Mutation interdite pour ce fichier (${access.reasonCodes.join(",")}).`
    );
  }
}
