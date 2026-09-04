/** Entités HTML nommées fréquentes dans les emails. */
const NAMED_HTML_ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  egrave: "è",
  eacute: "é",
  agrave: "à",
  ugrave: "ù",
  ocirc: "ô",
  icirc: "î",
  ucirc: "û",
  ecirc: "ê",
  acirc: "â",
  ccedil: "ç",
  euml: "ë",
  iuml: "ï",
  uuml: "ü",
  auml: "ä",
  ouml: "ö",
  rsquo: "'",
  lsquo: "'",
  rdquo: "\u201D",
  ldquo: "\u201C",
  ndash: "–",
  mdash: "—",
  hellip: "…",
  deg: "°",
  copy: "©",
  reg: "®",
  trade: "™",
  euro: "€",
};

/** Décode les entités HTML (&amp;, &#39;, &egrave;, etc.). */
export function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&#(\d+);/g, (_, code) =>
      String.fromCharCode(Number.parseInt(code, 10))
    )
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) =>
      String.fromCharCode(Number.parseInt(hex, 16))
    )
    .replace(/&([a-z]+);/gi, (match, name: string) => {
      const decoded = NAMED_HTML_ENTITIES[name.toLowerCase()];
      return decoded ?? match;
    });
}

/** Extrait un texte lisible depuis du HTML email (sans exécuter de scripts). */
export function htmlToPlainText(html: string): string {
  const withoutBlocks = html
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<\/div>/gi, "\n")
    .replace(/<\/tr>/gi, "\n")
    .replace(/<\/li>/gi, "\n")
    .replace(/<\/h[1-6]>/gi, "\n\n");

  const stripped = withoutBlocks.replace(/<[^>]+>/g, " ");
  return cleanPlainText(decodeHtmlEntities(stripped));
}

/** Nettoie le texte brut (espaces / lignes vides excessifs). */
export function cleanPlainText(text: string): string {
  return decodeHtmlEntities(text)
    .replace(/\r\n/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]{2,}/g, " ")
    .split("\n")
    .map((line) => line.trim())
    .filter((line, index, arr) => {
      if (line.length > 0) return true;
      return index > 0 && arr[index - 1]?.length > 0;
    })
    .join("\n")
    .trim();
}

export function sanitizeDisplayText(text: string, maxLength = 8000): string {
  const decoded = cleanPlainText(text);
  if (decoded.length <= maxLength) return decoded;
  return `${decoded.slice(0, maxLength)}…`;
}

/** Affichage plain text : conserve la structure des lignes, sans sur-trim. */
export function preparePlainTextForDisplay(
  text: string,
  maxLength = 50_000
): string {
  const normalized = decodeHtmlEntities(text)
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u00a0/g, " ")
    .replace(/\n{4,}/g, "\n\n\n")
    .trim();
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.slice(0, maxLength)}…`;
}

/** Prefère le plain text quand le HTML n'apporte pas de mise en page riche. */
export function shouldPreferPlainText(
  bodyText: string | undefined,
  bodyHtml: string | undefined
): boolean {
  const plain = (bodyText ?? "").trim();
  const html = (bodyHtml ?? "").trim();
  if (!html) return true;
  if (!plain) return false;

  const hasRichLayout = /<(table|img|td|th|blockquote)\b/i.test(html);
  if (hasRichLayout) return false;

  const fromHtml = htmlToPlainText(html);
  if (!fromHtml) return true;

  const plainNorm = cleanPlainText(plain).replace(/\s+/g, " ");
  const htmlNorm = fromHtml.replace(/\s+/g, " ");
  if (!plainNorm) return false;

  const overlap =
    plainNorm.length > 0
      ? Math.min(plainNorm.length, htmlNorm.length) /
        Math.max(plainNorm.length, htmlNorm.length)
      : 0;

  // Même contenu encapsulé (ex. Gmail div/pre autour d'un mail texte)
  if (overlap >= 0.72) return true;

  if (
    /<(div|pre|span|font|p)\b/i.test(html) &&
    !/<(table|img)\b/i.test(html) &&
    plainNorm.length >= 20
  ) {
    return true;
  }

  return false;
}

export function collapseLongUrls(text: string, maxLen = 72): string {
  return text.replace(/https?:\/\/[^\s)]+/g, (url) =>
    url.length > maxLen ? `${url.slice(0, maxLen)}…` : url
  );
}

/** Retire scripts et handlers inline d'un HTML email. */
export function sanitizeEmailHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/\son\w+\s*=\s*(['"])[\s\S]*?\1/gi, "")
    .replace(/\son\w+\s*=\s*[^\s>]+/gi, "")
    .replace(/javascript:/gi, "");
}

const WHITE_BG =
  /(?:#fff(?:fff)?|#fefefe|#fafafa|white|rgb\s*\(\s*255\s*,\s*255\s*,\s*255\s*\))/i;
const DARK_TEXT =
  /(?:#000(?:000)?|#111(?:111)?|#222(?:222)?|#333(?:333)?|black|rgb\s*\(\s*0\s*,\s*0\s*,\s*0\s*\))/i;

function stripLightBackgroundsFromStyle(style: string): string {
  return style
    .replace(/background-color\s*:\s*[^;]+/gi, (match) =>
      WHITE_BG.test(match) ? "background-color:transparent" : match
    )
    .replace(/background\s*:\s*[^;]+/gi, (match) =>
      WHITE_BG.test(match) ? "background:transparent" : match
    )
    .replace(/color\s*:\s*[^;]+/gi, (match) =>
      DARK_TEXT.test(match) ? "color:inherit" : match
    )
    // Borner les wrappers larges sans écraser les ratios de colonnes
    .replace(/max-width\s*:\s*(\d+)px/gi, (_, n: string) =>
      Number(n) >= 280 ? "max-width:100%" : `max-width:${n}px`
    )
    .replace(/min-width\s*:\s*(\d+)px/gi, (_, n: string) =>
      Number(n) >= 280 ? "min-width:0" : `min-width:${n}px`
    );
}

/** Prépare le HTML email pour affichage dark mode (sans iframe). */
export function prepareEmailHtmlForDarkDisplay(html: string): string {
  let safe = sanitizeEmailHtml(html);

  safe = safe.replace(/\sbgcolor\s*=\s*(['"])[^'"]*\1/gi, "");
  safe = safe.replace(/\sbgcolor\s*=\s*[^\s>]+/gi, "");

  safe = safe.replace(/\sstyle\s*=\s*(['"])([\s\S]*?)\1/gi, (_, quote, style) => {
    return ` style=${quote}${stripLightBackgroundsFromStyle(style)}${quote}`;
  });

  safe = safe.replace(
    /<font([^>]*)\scolor\s*=\s*(['"])[^'"]*\2/gi,
    "<font$1"
  );

  return safe;
}

export function wrapEmailHtmlDocument(html: string): string {
  const safe = prepareEmailHtmlForDarkDisplay(html);
  // CSS volontairement prudent : forcer width:100% sur tous les td
  // casse les layouts Google (colonnes spacer) → colonne ultra-étroite.
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><meta name="color-scheme" content="dark"><base target="_blank" rel="noopener noreferrer"><style>
html,body{margin:0;padding:0;background:#18181a !important;color:#e2e2e6 !important;font-family:system-ui,-apple-system,BlinkMacSystemFont,sans-serif;line-height:1.55;width:100%;max-width:100%;overflow-x:auto;-webkit-text-size-adjust:100%;overflow-wrap:break-word;word-wrap:break-word;}
body{padding:12px;font-size:16px;}
*{box-sizing:border-box;}
img,video{max-width:100% !important;height:auto !important;}
/* Seulement les wrappers racine — pas les td internes */
body > table,body > center,body > div{max-width:100% !important;}
body > center{display:block;width:100%;text-align:left;}
table{max-width:100% !important;border-collapse:collapse;}
td,th{overflow-wrap:break-word;word-wrap:break-word;}
pre,code{white-space:pre-wrap !important;word-break:break-word !important;max-width:100%;}
a{color:#74a3e0 !important;}
td,th,div,p,span,h1,h2,h3,h4,font,li{background-color:transparent !important;color:inherit !important;}
</style></head><body>${safe}</body></html>`;
}
