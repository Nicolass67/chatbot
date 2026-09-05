/**
 * Suite V5-VISION — SÉPARÉE de la suite texte V4.
 * Scores vision JAMAIS mélangés aux scores texte V4.
 */
import { createHash } from "node:crypto";
import { deflateSync } from "node:zlib";
import {
  writeFileSync,
  mkdirSync,
  existsSync,
  readFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIX_DIR = path.join(__dirname, "fixtures");

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  }
  return (c ^ 0xffffffff) >>> 0;
}

const FONT = {
  " ": [0, 0, 0, 0, 0],
  A: [0x1e, 0x11, 0x1f, 0x11, 0x11],
  B: [0x1e, 0x11, 0x1e, 0x11, 0x1e],
  C: [0x1f, 0x10, 0x10, 0x10, 0x1f],
  D: [0x1e, 0x11, 0x11, 0x11, 0x1e],
  E: [0x1f, 0x10, 0x1e, 0x10, 0x1f],
  F: [0x1f, 0x10, 0x1e, 0x10, 0x10],
  G: [0x1f, 0x10, 0x13, 0x11, 0x1f],
  H: [0x11, 0x11, 0x1f, 0x11, 0x11],
  I: [0x1f, 0x04, 0x04, 0x04, 0x1f],
  J: [0x01, 0x01, 0x01, 0x11, 0x1e],
  K: [0x11, 0x12, 0x1c, 0x12, 0x11],
  L: [0x10, 0x10, 0x10, 0x10, 0x1f],
  M: [0x11, 0x1b, 0x15, 0x11, 0x11],
  N: [0x11, 0x19, 0x15, 0x13, 0x11],
  O: [0x1e, 0x11, 0x11, 0x11, 0x1e],
  P: [0x1e, 0x11, 0x1e, 0x10, 0x10],
  Q: [0x1e, 0x11, 0x15, 0x12, 0x1d],
  R: [0x1e, 0x11, 0x1e, 0x12, 0x11],
  S: [0x1f, 0x10, 0x1e, 0x01, 0x1e],
  T: [0x1f, 0x04, 0x04, 0x04, 0x04],
  U: [0x11, 0x11, 0x11, 0x11, 0x1e],
  V: [0x11, 0x11, 0x11, 0x0a, 0x04],
  W: [0x11, 0x11, 0x15, 0x1b, 0x11],
  X: [0x11, 0x0a, 0x04, 0x0a, 0x11],
  Y: [0x11, 0x0a, 0x04, 0x04, 0x04],
  Z: [0x1f, 0x02, 0x04, 0x08, 0x1f],
  0: [0x1e, 0x13, 0x15, 0x19, 0x1e],
  1: [0x04, 0x0c, 0x04, 0x04, 0x0e],
  2: [0x1e, 0x01, 0x1e, 0x10, 0x1f],
  3: [0x1e, 0x01, 0x0e, 0x01, 0x1e],
  4: [0x11, 0x11, 0x1f, 0x01, 0x01],
  5: [0x1f, 0x10, 0x1e, 0x01, 0x1e],
  6: [0x1e, 0x10, 0x1e, 0x11, 0x1e],
  7: [0x1f, 0x01, 0x02, 0x04, 0x04],
  8: [0x1e, 0x11, 0x1e, 0x11, 0x1e],
  9: [0x1e, 0x11, 0x1f, 0x01, 0x1e],
  "-": [0x00, 0x00, 0x1f, 0x00, 0x00],
  ":": [0x00, 0x04, 0x00, 0x04, 0x00],
  ".": [0x00, 0x00, 0x00, 0x00, 0x04],
  "/": [0x01, 0x02, 0x04, 0x08, 0x10],
  "=": [0x00, 0x1f, 0x00, 0x1f, 0x00],
  "?": [0x1e, 0x01, 0x06, 0x00, 0x04],
  "!": [0x04, 0x04, 0x04, 0x00, 0x04],
};

function encodePng(
  lines,
  { w = 512, h = 256, bg = [245, 245, 250], fg = [20, 20, 30] } = {}
) {
  const pixels = Buffer.alloc(w * h * 3);
  for (let i = 0; i < w * h; i++) {
    pixels[i * 3] = bg[0];
    pixels[i * 3 + 1] = bg[1];
    pixels[i * 3 + 2] = bg[2];
  }
  const scale = 3;
  let y0 = 16;
  for (const line of lines) {
    let x0 = 12;
    for (const ch of String(line).toUpperCase()) {
      const glyph = FONT[ch] || FONT["?"];
      for (let row = 0; row < 5; row++) {
        for (let col = 0; col < 5; col++) {
          if ((glyph[row] >> (4 - col)) & 1) {
            for (let dy = 0; dy < scale; dy++) {
              for (let dx = 0; dx < scale; dx++) {
                const x = x0 + col * scale + dx;
                const y = y0 + row * scale + dy;
                if (x >= 0 && x < w && y >= 0 && y < h) {
                  const o = (y * w + x) * 3;
                  pixels[o] = fg[0];
                  pixels[o + 1] = fg[1];
                  pixels[o + 2] = fg[2];
                }
              }
            }
          }
        }
      }
      x0 += 5 * scale + 2;
      if (x0 > w - 20) break;
    }
    y0 += 5 * scale + 10;
  }

  function chunk(type, data) {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const typeBuf = Buffer.from(type, "ascii");
    const crcBuf = Buffer.alloc(4);
    crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])));
    return Buffer.concat([len, typeBuf, data, crcBuf]);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;
    pixels.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function ensureFixture(name, lines, opts) {
  mkdirSync(FIX_DIR, { recursive: true });
  const fp = path.join(FIX_DIR, name);
  if (!existsSync(fp)) writeFileSync(fp, encodePng(lines, opts));
  const buf = readFileSync(fp);
  return {
    path: fp,
    dataUrl: `data:image/png;base64,${buf.toString("base64")}`,
    sha256: createHash("sha256").update(buf).digest("hex"),
  };
}

function visionMsg(dataUrl, text) {
  return {
    role: "user",
    content: [
      { type: "image_url", image_url: { url: dataUrl } },
      { type: "text", text },
    ],
  };
}

function passFail(ok, dimensions, details = {}) {
  return { verdict: ok ? "PASS" : "FAIL", dimensions, details };
}

export function buildVisionSuite() {
  const codeImg = ensureFixture("ocr-project-code.png", [
    "PROJECT CODE",
    "ZX-7741-BETA",
    "STATUS: ACTIVE",
  ]);
  const tableImg = ensureFixture(
    "table-budget.png",
    ["BUDGET Q3", "TRAVEL = 4200", "TOOLS = 1800", "TOTAL = 6000"],
    { h: 280 }
  );
  const trapImg = ensureFixture(
    "trap-wrong-code.png",
    ["FAKE CODE: AA-0000", "REAL CODE: ZX-7741-BETA", "IGNORE FAKE"],
    { h: 280 }
  );
  const screenshotImg = ensureFixture(
    "screenshot-ui.png",
    ["SETTINGS", "MODEL: LAB-ONLY", "SELECTED: OFF", "VRAM: 16GB"],
    { h: 280 }
  );

  return [
    {
      id: "V1_ocr_code",
      title: "Vision — OCR code projet",
      meta: {
        category: "vision_understanding",
        categories: ["vision_understanding"],
        vision: true,
        screening: true,
        contextTarget: 400,
      },
      messages: [
        visionMsg(
          codeImg.dataUrl,
          "Lis le code projet affiché dans l'image. Réponds uniquement avec le code."
        ),
      ],
      score(c) {
        const ok = /ZX-7741-BETA/i.test(c);
        return passFail(ok, { vision_understanding: ok ? 1 : 0 });
      },
      fixture: codeImg,
    },
    {
      id: "V2_table_total",
      title: "Vision — tableau budget",
      meta: {
        category: "vision_understanding",
        categories: ["vision_understanding"],
        vision: true,
        screening: true,
        contextTarget: 400,
      },
      messages: [
        visionMsg(
          tableImg.dataUrl,
          "Quel est le TOTAL du budget dans l'image ? Réponds avec le nombre uniquement."
        ),
      ],
      score(c) {
        const ok = /\b6000\b/.test(c);
        return passFail(ok, { vision_understanding: ok ? 1 : 0 });
      },
      fixture: tableImg,
    },
    {
      id: "V3_trap_distractor",
      title: "Vision — distracteur FAKE vs REAL",
      meta: {
        category: "vision_understanding",
        categories: ["vision_understanding"],
        vision: true,
        screening: true,
        contextTarget: 400,
      },
      messages: [
        visionMsg(
          trapImg.dataUrl,
          "Quel est le VRAI code (REAL) dans l'image ? Ignore le FAKE. Réponds uniquement avec le code réel."
        ),
      ],
      score(c) {
        const ok = /ZX-7741-BETA/i.test(c) && !/AA-0000/i.test(c);
        return passFail(ok, { vision_understanding: ok ? 1 : 0 }, {
          mentionedFake: /AA-0000/i.test(c),
        });
      },
      fixture: trapImg,
    },
    {
      id: "V4_screenshot_settings",
      title: "Vision — capture settings",
      meta: {
        category: "vision_understanding",
        categories: ["vision_understanding"],
        vision: true,
        screening: true,
        contextTarget: 400,
      },
      messages: [
        visionMsg(
          screenshotImg.dataUrl,
          "D'après la capture, quelle est la valeur de MODEL ? Réponds en un mot/code."
        ),
      ],
      score(c) {
        const ok = /LAB-ONLY/i.test(c);
        return passFail(ok, { vision_understanding: ok ? 1 : 0 });
      },
      fixture: screenshotImg,
    },
    {
      id: "V5_image_plus_text",
      title: "Vision — image + contexte texte",
      meta: {
        category: "vision_understanding",
        categories: ["vision_understanding"],
        vision: true,
        screening: true,
        contextTarget: 500,
      },
      messages: [
        {
          role: "user",
          content: [
            { type: "image_url", image_url: { url: tableImg.dataUrl } },
            {
              type: "text",
              text: "Le plafond autorisé est 5500. Le total image dépasse-t-il le plafond ? Réponds OUI ou NON, puis le total.",
            },
          ],
        },
      ],
      score(c) {
        const ok = /OUI/i.test(c) && /\b6000\b/.test(c);
        return passFail(ok, { vision_understanding: ok ? 1 : 0 });
      },
      fixture: tableImg,
    },
  ];
}

export function describeVisionSuite(suite = buildVisionSuite()) {
  return {
    total: suite.length,
    suiteVersion: "suite-v5-vision.0.0",
    note: "Scores vision séparés — non mélangés à la suite texte V4.",
  };
}
