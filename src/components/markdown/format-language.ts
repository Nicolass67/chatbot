const LANGUAGE_LABELS: Record<string, string> = {
  bash: "Bash",
  sh: "Shell",
  shell: "Shell",
  c: "C",
  cpp: "C++",
  cs: "C#",
  css: "CSS",
  html: "HTML",
  java: "Java",
  js: "JavaScript",
  javascript: "JavaScript",
  json: "JSON",
  kotlin: "Kotlin",
  md: "Markdown",
  markdown: "Markdown",
  py: "Python",
  python: "Python",
  sql: "SQL",
  text: "Text",
  plaintext: "Text",
  ts: "TypeScript",
  tsx: "TypeScript",
  typescript: "TypeScript",
  xml: "XML",
  yaml: "YAML",
  yml: "YAML",
};

export function formatLanguage(language: string): string {
  const key = language.trim().toLowerCase();
  return LANGUAGE_LABELS[key] ?? language.charAt(0).toUpperCase() + language.slice(1);
}
