import type { ToolDefinition } from "@/lib/runtime/types";
import type { Tool } from "./types";
import { zodToJsonSchema } from "./types";
import { emailTools, emailSendInternalTool } from "./email";
import { fileTools } from "./files";
import { webSearchTool } from "./web-search/tool";

const tools: Tool[] = [
  webSearchTool,
  ...emailTools,
  emailSendInternalTool,
  ...fileTools,
];

const FILE_READ_ONLY = new Set([
  "file_search",
  "file_list",
  "file_stat",
  "file_read",
  "file_analyze",
]);

const FILE_MUTATION_PROPOSE = new Set([
  "file_create_directory",
  "file_rename",
  "file_move",
]);

export function getRegisteredTools(options: {
  webSearchEnabled: boolean;
  emailEnabled?: boolean;
  emailToolCandidates?: string[];
  filesEnabled?: boolean;
  fileToolCandidates?: string[];
}): Tool[] {
  return tools.filter((t) => {
    if (t.name === "email_send") return false;
    if (t.name.startsWith("email_")) {
      // Email tools uniquement si candidats explicites (ex. conversation scope=mail).
      // emailEnabled seul ne suffit pas — le chat général reste sans outils email.
      if (!options.emailEnabled) return false;
      if (
        !options.emailToolCandidates ||
        options.emailToolCandidates.length === 0
      ) {
        return false;
      }
      return options.emailToolCandidates.includes(t.name);
    }
    if (t.name === "web_search") return options.webSearchEnabled;
    if (FILE_READ_ONLY.has(t.name) || FILE_MUTATION_PROPOSE.has(t.name)) {
      // Comme email : pas de candidats → pas d'outils fichiers au LLM.
      // Évite file_search quand le routeur n'a pas classé d'intent files.
      if (!options.filesEnabled) return false;
      if (
        !options.fileToolCandidates ||
        options.fileToolCandidates.length === 0
      ) {
        return false;
      }
      return options.fileToolCandidates.includes(t.name);
    }
    return true;
  });
}

export function getTool(name: string): Tool | undefined {
  return tools.find((t) => t.name === name);
}

export function getToolDefinitions(options: {
  webSearchEnabled: boolean;
  emailEnabled?: boolean;
  emailToolCandidates?: string[];
  filesEnabled?: boolean;
  fileToolCandidates?: string[];
}): ToolDefinition[] {
  return getRegisteredTools(options).map((tool) => ({
    type: "function" as const,
    function: {
      name: tool.name,
      description: tool.description,
      parameters: zodToJsonSchema(tool.inputSchema),
    },
  }));
}

export async function executeToolRaw(
  name: string,
  args: unknown,
  ctx: Parameters<Tool["execute"]>[1]
): Promise<unknown> {
  const tool = getTool(name);
  if (!tool) {
    throw new Error(`Outil inconnu: ${name}`);
  }
  const parsed = tool.inputSchema.parse(args);
  return tool.execute(parsed, ctx);
}

/** @deprecated Préférer executeToolWithPolicy — conservé pour compatibilité tests internes. */
export const executeTool = executeToolRaw;
