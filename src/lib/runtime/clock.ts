/** Horloge runtime — date calculée à l'exécution, jamais hardcodée. */

export interface RuntimeClock {
  currentDate: string;
  currentDateTime: string;
  timezone: string;
  currentYear: number;
  currentMonth: number;
}

const DEFAULT_TIMEZONE = "Europe/Paris";

export function getRuntimeClock(
  now: Date = new Date(),
  timezone: string = DEFAULT_TIMEZONE
): RuntimeClock {
  const dateFormatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });

  const dateTimeFormatter = new Intl.DateTimeFormat("fr-FR", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });

  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "numeric",
  }).formatToParts(now);

  const year = Number(parts.find((p) => p.type === "year")?.value ?? now.getFullYear());
  const month = Number(parts.find((p) => p.type === "month")?.value ?? now.getMonth() + 1);

  return {
    currentDate: dateFormatter.format(now),
    currentDateTime: dateTimeFormatter.format(now),
    timezone,
    currentYear: year,
    currentMonth: month,
  };
}
