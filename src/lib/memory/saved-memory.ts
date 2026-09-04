export interface SavedMemoryItem {
  id: string;
  content: string;
  category: string;
}

export const MEMORY_CATEGORY_LABELS: Record<string, string> = {
  preference: "Préférence",
  hardware: "Matériel",
  project: "Projet",
  habit: "Habitude",
  communication: "Communication",
  other: "Autre",
};

export function memoryCategoryLabel(category: string): string {
  return MEMORY_CATEGORY_LABELS[category] ?? "Mémoire";
}
