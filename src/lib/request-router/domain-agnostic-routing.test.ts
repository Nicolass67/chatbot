import { describe, expect, it } from "vitest";
import type { RuntimeClock } from "@/lib/runtime/clock";
import { routeRequestSync } from "./route-request";

const SEPT_2026_CLOCK: RuntimeClock = {
  currentDate: "2026-09-01",
  currentDateTime: "01/09/2026 12:00:00",
  timezone: "Europe/Paris",
  currentYear: 2026,
  currentMonth: 9,
};

function route(message: string, extra: Partial<Parameters<typeof routeRequestSync>[0]> = {}) {
  return routeRequestSync({
    message,
    webSearchEnabled: true,
    chatMode: "chat",
    imageCount: 0,
    attachmentCount: 0,
    modelId: "",
    clock: SEPT_2026_CLOCK,
    ...extra,
  });
}

type CurrentCase = {
  message: string;
  paraphrases?: string[];
};

const CURRENT_DATA_CASES: CurrentCase[] = [
  { message: "Quel est le prix actuel du bitcoin ?" },
  { message: "Quel est le prix actuel du cuivre ?" },
  { message: "Quelle est la température actuelle à Strasbourg ?" },
  { message: "Qui est actuellement Premier ministre du Royaume-Uni ?" },
  {
    message: "Quels sont les derniers benchmarks de cette carte graphique ?",
  },
  { message: "Trouve-moi un billet Paris Tokyo pour demain" },
  { message: "Quels sont les derniers résultats financiers de NVIDIA ?" },
  {
    message:
      "Donne-moi les dernières données disponibles sur le marché de l'uranium enrichi au Kazakhstan",
  },
];

const STATIC_CASES = [
  {
    current: "Quel est le prix actuel du bitcoin ?",
    historical: "Quel était le prix du bitcoin en 2019 ?",
  },
  {
    current: "Quelle est la température actuelle à Strasbourg ?",
    historical: "Quelle était la météo à Strasbourg le 14 juillet 1998 ?",
  },
  {
    current: "Qui est actuellement Premier ministre du Royaume-Uni ?",
    historical: "Qui était Premier ministre du Royaume-Uni en 1990 ?",
  },
];

describe("domain-agnostic routing — données actuelles", () => {
  for (const testCase of CURRENT_DATA_CASES) {
    const messages = [testCase.message, ...(testCase.paraphrases ?? [])];

    for (const message of messages) {
      it(`« ${message.slice(0, 60)}… » → web required`, () => {
        const decision = route(message);
        expect(decision.knowledge).not.toBe("static");
        expect(decision.web.mode).toBe("required");
        expect(decision.web.searchQuery.length).toBeGreaterThan(0);
      });
    }
  }

  it("domaine inédit (uranium Kazakhstan) sans logique codée — web required", () => {
    const decision = route(
      "Donne-moi les dernières données disponibles sur le marché de l'uranium enrichi au Kazakhstan"
    );
    expect(decision.knowledge).toBe("current");
    expect(decision.web.mode).toBe("required");
    expect(["single", "research"]).toContain(decision.web.searchType);
  });
});

describe("domain-agnostic routing — questions historiques", () => {
  for (const pair of STATIC_CASES) {
    it(`historique : ${pair.historical.slice(0, 50)}…`, () => {
      const decision = route(pair.historical);
      expect(decision.temporal.scope).toBe("historical");
      expect(decision.web.mode).toBe("none");
    });
  }
});

describe("domain-agnostic routing — recherche approfondie", () => {
  it("comparaison multi-sujets → research ou web required", () => {
    const decision = route(
      "Compare les dernières données sur le cuivre, le cacao et l'uranium"
    );
    expect(decision.web.mode).toBe("required");
    expect(["single", "research"]).toContain(decision.web.searchType);
  });
});
