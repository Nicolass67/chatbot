import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import {
  analyzeTemporalContext,
  buildWebSearchTemporalInput,
  validateWebSearchQuery,
} from "./temporal";
import { getRuntimeClock, type RuntimeClock } from "@/lib/runtime/clock";

const SEPT_2026_CLOCK: RuntimeClock = {
  currentDate: "2026-09-01",
  currentDateTime: "01/09/2026 12:00:00",
  timezone: "Europe/Paris",
  currentYear: 2026,
  currentMonth: 9,
};

const userGoalCurrent =
  "Trouve-moi les trois meilleurs GPU disponibles en France sous 1000 € actuellement";

describe("analyzeTemporalContext", () => {
  it("sans marqueur temporel → unspecified (pas de déduction métier)", () => {
    const ctx = analyzeTemporalContext(
      "Trouve-moi les meilleurs GPU sous 1000 €",
      SEPT_2026_CLOCK
    );
    expect(ctx.scope).toBe("unspecified");
    expect(ctx.isTimeSensitive).toBe(false);
  });

  it("détecte une demande historique explicite 2024", () => {
    const ctx = analyzeTemporalContext(
      "meilleurs GPU en 2024",
      SEPT_2026_CLOCK
    );
    expect(ctx.scope).toBe("historical");
    expect(ctx.referenceYear).toBe(2024);
  });

  it("détecte actuellement comme current", () => {
    const ctx = analyzeTemporalContext(
      "meilleurs GPU actuellement",
      SEPT_2026_CLOCK
    );
    expect(ctx.scope).toBe("current");
  });

  it("détecte les dernières données comme recent", () => {
    const ctx = analyzeTemporalContext(
      "quelles sont les dernières données disponibles sur le sujet",
      SEPT_2026_CLOCK
    );
    expect(ctx.scope).toBe("recent");
    expect(ctx.isTimeSensitive).toBe(true);
  });

  it("détecte demain comme future", () => {
    const ctx = analyzeTemporalContext(
      "Quel temps fera-t-il demain à Strasbourg ?",
      SEPT_2026_CLOCK
    );
    expect(ctx.scope).toBe("future");
  });
});

describe("validateWebSearchQuery", () => {
  const userGoalCurrent =
    "Trouve-moi les trois meilleurs GPU disponibles en France sous 1000 € actuellement";

  it("retire 2024 pour une demande current", () => {
    const temporal = analyzeTemporalContext(userGoalCurrent, SEPT_2026_CLOCK);
    const result = validateWebSearchQuery(
      "meilleurs GPU sous 1000 € 2024",
      userGoalCurrent,
      temporal
    );
    expect(result.corrected).toBe(true);
    expect(result.query).not.toMatch(/\b2024\b/);
  });

  it("conserve 2024 si l'utilisateur l'a demandé", () => {
    const goal = "meilleurs GPU en 2024";
    const temporal = analyzeTemporalContext(goal, SEPT_2026_CLOCK);
    const result = validateWebSearchQuery(
      "meilleurs GPU 2024 comparatif",
      goal,
      temporal
    );
    expect(result.query).toMatch(/2024/);
  });

  it("n'ajoute pas 2026 naïvement partout", () => {
    const temporal = analyzeTemporalContext(userGoalCurrent, SEPT_2026_CLOCK);
    const built = buildWebSearchTemporalInput(
      "meilleurs GPU sous 1000 €",
      userGoalCurrent,
      temporal
    );
    expect(built.query).not.toMatch(/\b2026\b/);
  });
});

describe("getRuntimeClock", () => {
  it("calcule la date dynamiquement", () => {
    const clock = getRuntimeClock(new Date("2026-09-01T10:00:00Z"));
    expect(clock.currentYear).toBe(2026);
    expect(clock.timezone).toBe("Europe/Paris");
    expect(clock.currentDate).toMatch(/2026-09-01/);
  });
});

describe("logTemporalSearchDebug", () => {
  beforeEach(() => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    vi.stubEnv("NODE_ENV", "development");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.restoreAllMocks();
  });

  it("log les infos temporelles en développement", () => {
    const temporal = analyzeTemporalContext(userGoalCurrent, SEPT_2026_CLOCK);
    buildWebSearchTemporalInput(
      "meilleurs GPU sous 1000 € 2024",
      userGoalCurrent,
      temporal
    );
    expect(console.log).toHaveBeenCalled();
  });
});
