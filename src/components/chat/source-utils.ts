export function faviconUrl(domain: string): string {
  const host = domain.replace(/^www\./, "");
  return `https://www.google.com/s2/favicons?domain=${encodeURIComponent(host)}&sz=32`;
}

export function domainInitial(domain: string): string {
  const host = domain.replace(/^www\./, "");
  return (host.charAt(0) || "?").toUpperCase();
}
