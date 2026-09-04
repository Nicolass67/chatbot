import { emailAnalyzeTool } from "./analyze";
import { emailCreateDraftTool } from "./create-draft";
import { emailGetThreadTool } from "./get-thread";
import { emailListTool } from "./list";
import { emailSearchTool } from "./search";

export const emailTools = [
  emailListTool,
  emailSearchTool,
  emailGetThreadTool,
  emailAnalyzeTool,
  emailCreateDraftTool,
] as const;

export { emailAnalyzeTool } from "./analyze";
export { emailCreateDraftTool } from "./create-draft";
export { emailGetThreadTool } from "./get-thread";
export { emailListTool } from "./list";
export { emailSearchTool } from "./search";
export { emailSendInternalTool } from "./send";
