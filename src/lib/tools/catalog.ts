/** Métadonnées des outils — futurs outils non encore implémentés. */

export interface ToolCatalogEntry {
  name: string;
  description: string;
  implemented: boolean;
}

export const TOOL_CATALOG: ToolCatalogEntry[] = [
  {
    name: "web_search",
    description: "Recherche sur le Web via DuckDuckGo",
    implemented: true,
  },
  {
    name: "file_search",
    description: "Recherche de fichiers locaux (metadata)",
    implemented: true,
  },
  {
    name: "file_list",
    description: "Liste un dossier local via fileId",
    implemented: true,
  },
  {
    name: "file_stat",
    description: "Métadonnées d'un fichier local via fileId",
    implemented: true,
  },
  {
    name: "file_read",
    description: "Lecture texte d'un fichier local via fileId",
    implemented: true,
  },
  {
    name: "file_analyze",
    description: "Analyse / résumé d'un document local via fileId",
    implemented: true,
  },
  {
    name: "file_create_directory",
    description: "Propose la création d'un dossier (confirmation)",
    implemented: true,
  },
  {
    name: "file_rename",
    description: "Propose un renommage (confirmation)",
    implemented: true,
  },
  {
    name: "file_move",
    description: "Propose un déplacement (confirmation)",
    implemented: true,
  },
  {
    name: "calculator",
    description: "Calculatrice pour expressions mathématiques",
    implemented: false,
  },
  {
    name: "python",
    description: "Exécution de code Python en sandbox",
    implemented: false,
  },
  {
    name: "web_fetch",
    description: "Récupération du contenu d'une URL",
    implemented: false,
  },
  {
    name: "conversation_search",
    description: "Recherche dans l'historique de conversation",
    implemented: false,
  },
];

export function getImplementedToolNames(): string[] {
  return TOOL_CATALOG.filter((t) => t.implemented).map((t) => t.name);
}

export function getFutureToolNames(): string[] {
  return TOOL_CATALOG.filter((t) => !t.implemented).map((t) => t.name);
}
