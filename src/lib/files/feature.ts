import { getEnv } from "@/lib/config/env";
import {
  DEFAULT_FILES_CAPABILITIES,
  type FilesCapabilities,
} from "./types";

export function isFilesFeatureEnabled(): boolean {
  return getEnv().FILES_ENABLED === true;
}

export function assertFilesFeatureEnabled(): void {
  if (!isFilesFeatureEnabled()) {
    throw new Error(
      "La fonctionnalité Files est désactivée (FILES_ENABLED=false)."
    );
  }
}

/** Capabilities effectives — V1 defaults ; settings pourront override plus tard. */
export function getFilesCapabilities(
  override?: Partial<FilesCapabilities> | null
): FilesCapabilities {
  return {
    ...DEFAULT_FILES_CAPABILITIES,
    ...override,
  };
}
