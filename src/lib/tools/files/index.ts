import { fileAnalyzeTool } from "./analyze";
import { fileListTool } from "./list";
import {
  fileCreateDirectoryTool,
  fileMoveTool,
  fileRenameTool,
} from "./mutations-tools";
import { fileReadTool } from "./read";
import { fileSearchTool } from "./search";
import { fileStatTool } from "./stat";

export const fileReadOnlyTools = [
  fileSearchTool,
  fileListTool,
  fileStatTool,
  fileReadTool,
  fileAnalyzeTool,
];

export const fileMutationProposeTools = [
  fileCreateDirectoryTool,
  fileRenameTool,
  fileMoveTool,
];

export const fileTools = [...fileReadOnlyTools, ...fileMutationProposeTools];
