export {
  classifyRelativePathAccess,
  isSensitiveRelativePath,
} from "./access";
export { LIMITS, SEARCH_SNIPPET_MAX_CHARS } from "./constants";
export {
  cancelFilesMutationAction,
  confirmFilesMutationAction,
} from "./confirm";
export { isFilesFeatureEnabled } from "./feature";
export {
  buildFilesHandoffUrl,
  handoffMessageForFilesIntent,
} from "./handoff";
export {
  indexRootFiles,
  purgeIndexForRoot,
  searchFileIndexPassages,
} from "./index-service";
export { resolveUnderRoot } from "./path-guard";
export { listDirectory, searchMetadata } from "./provider";
export { mintFileReference } from "./references";
export { resolveFileReference, resolvePathToFile } from "./resolve";
export {
  addFileRoot,
  ensureDefaultRoots,
  hasConfiguredRoots,
  listEnabledFileRoots,
  listFileRoots,
  removeFileRoot,
  setFileRootEnabled,
} from "./roots";
