import type { InformationNeed } from "./types";

/**
 * Décompose la question en besoins d'information génériques.
 * Aucune catégorie métier hardcodée (marques/produits/domaines).
 */
export function deriveInformationNeeds(
  question: string,
  priorUserMessages: string[] = []
): InformationNeed[] {
  const q = question.trim();
  const priors = priorUserMessages.map((m) => m.trim()).filter(Boolean);
  const blob = [q, ...priors.slice(-3)].join("\n");

  const needs: InformationNeed[] = [
    {
      id: "need_primary",
      description: `Répondre précisément à : ${q.slice(0, 160)}`,
      priority: "critical",
      status: "open",
    },
  ];

  if (priors.length > 0 && isLikelyElliptical(q)) {
    needs.push({
      id: "need_resolve_reference",
      description:
        "Résoudre les références implicites du tour précédent (entités / contraintes)",
      priority: "critical",
      status: "open",
    });
  }

  // Entités candidates (noms propres / intitulés entre guillemets / tokens capitalisés)
  const entities = extractGenericEntities(blob);
  if (entities.length >= 2) {
    needs.push({
      id: "need_entities",
      description: `Couvrir les entités évoquées : ${entities.slice(0, 6).join(", ")}`,
      priority: "high",
      status: "open",
    });
  }

  // Contraintes numériques / budgétaires génériques
  if (/\d/.test(blob) && /(?:€|\$|eur|usd|%|max|min|moins|plus|entre|sous|budget|jusqu)/i.test(blob)) {
    needs.push({
      id: "need_constraints",
      description: "Respecter les contraintes numériques / budget / seuils indiqués",
      priority: "high",
      status: "open",
    });
  }

  // Attributs / critères (listes, « et », comparaisons)
  const parts = splitInformationalParts(blob);
  for (let i = 0; i < Math.min(parts.length, 4); i++) {
    needs.push({
      id: `need_part_${i + 1}`,
      description: parts[i]!.slice(0, 160),
      priority: i === 0 ? "high" : "medium",
      status: "open",
    });
  }

  if (/\b(compar|vs|versus|différence|alternative|meilleur|top|classement)/i.test(blob)) {
    needs.push({
      id: "need_compare",
      description: "Comparer les options sur les critères mentionnés et produire un classement si demandé",
      priority: "high",
      status: "open",
    });
  }

  if (/\b(recommand|choisir|quel|lequel|préfèr|prefer)/i.test(blob)) {
    needs.push({
      id: "need_recommendation",
      description: "Fournir une recommandation actionnable fondée sur les preuves",
      priority: "high",
      status: "open",
    });
  }

  return dedupeNeeds(needs);
}

function dedupeNeeds(needs: InformationNeed[]): InformationNeed[] {
  const seen = new Set<string>();
  const out: InformationNeed[] = [];
  for (const n of needs) {
    if (seen.has(n.id)) continue;
    seen.add(n.id);
    out.push(n);
  }
  return out;
}

function extractGenericEntities(text: string): string[] {
  const out: string[] = [];
  const quoted = text.match(/[«"]([^«»"]{2,60})[»"]/g) ?? [];
  for (const q of quoted) {
    out.push(q.replace(/[«»"]/g, "").trim());
  }
  const caps = text.match(/\b[A-ZÀ-Ü][A-Za-zÀ-ÿ0-9][A-Za-zÀ-ÿ0-9+\-]{1,40}\b/g) ?? [];
  for (const c of caps) {
    if (/^(Je|Tu|Il|Elle|On|Nous|Vous|Ils|Les|Des|Une|Pour|Avec|Dans|Sur|The|And|For)$/i.test(c)) continue;
    out.push(c);
  }
  return [...new Set(out.map((s) => s.trim()).filter((s) => s.length >= 2))].slice(0, 8);
}

function isLikelyElliptical(message: string): boolean {
  const t = message.trim();
  if (t.length < 48) return true;
  return /^(et|mais|donc|alors|ok)\b/i.test(t) || /\b(celui|celle|ça|les|leur)\b/i.test(t);
}

function splitInformationalParts(text: string): string[] {
  return text
    .split(/[?;]|\bet\b|\bpuis\b|\baussi\b/i)
    .map((s) => s.trim())
    .filter((s) => s.length >= 12)
    .slice(0, 6);
}
