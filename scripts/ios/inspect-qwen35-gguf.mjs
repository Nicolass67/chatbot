import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

const bin =
  "D:/chatbot-public/apps/ios/Vendor/build-apple/llama.xcframework/ios-arm64/llama.framework/llama";
const buf = readFileSync(bin);
const needles = [
  "mtmd_init_from_file",
  "mtmd_tokenize",
  "mtmd_helper_eval_chunks",
  "mtmd_support_vision",
  "mtmd_default_marker",
  "mtmd_get_cap_from_file",
  "llama_version",
];
const symbols = {};
for (const n of needles) {
  symbols[n] = buf.includes(Buffer.from(n));
}
console.log("binaryBytes", buf.length);
console.log("mtmdSymbols", symbols);

const outDir = "D:/chatbot-public/artifacts";
if (!existsSync(outDir)) mkdirSync(outDir, { recursive: true });

async function fetchRange(url, n = 1024 * 1024) {
  const res = await fetch(url, {
    headers: {
      Range: `bytes=0-${n - 1}`,
      "User-Agent": "chatbot-gguf-inspect",
    },
    redirect: "follow",
  });
  const ab = await res.arrayBuffer();
  return { status: res.status, buf: Buffer.from(ab) };
}

function readU32(b, off) {
  return b.readUInt32LE(off);
}
function readU64(b, off) {
  return Number(b.readBigUInt64LE(off));
}

function parseGguf(b, label) {
  if (b.toString("utf8", 0, 4) !== "GGUF") {
    return { label, error: "not GGUF", magic: b.slice(0, 8).toString("hex") };
  }
  let off = 4;
  const version = readU32(b, off);
  off += 4;
  const tensorCount = readU64(b, off);
  off += 8;
  const kvCount = readU64(b, off);
  off += 8;
  const kv = {};

  function readString() {
    const n = readU64(b, off);
    off += 8;
    const s = b.toString("utf8", off, off + n);
    off += n;
    return s.replace(/\0+$/, "");
  }

  function readValue(t) {
    switch (t) {
      case 0:
        return b.readUInt8(off++);
      case 1:
        return b.readInt8(off++);
      case 2: {
        const v = b.readUInt16LE(off);
        off += 2;
        return v;
      }
      case 3: {
        const v = b.readInt16LE(off);
        off += 2;
        return v;
      }
      case 4: {
        const v = b.readUInt32LE(off);
        off += 4;
        return v;
      }
      case 5: {
        const v = b.readInt32LE(off);
        off += 4;
        return v;
      }
      case 6: {
        const v = b.readFloatLE(off);
        off += 4;
        return v;
      }
      case 7:
        return b.readUInt8(off++) !== 0;
      case 8:
        return readString();
      case 9: {
        const at = readU32(b, off);
        off += 4;
        const n = readU64(b, off);
        off += 8;
        const sizes = { 0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8 };
        if (at === 8) {
          const sample = [];
          for (let i = 0; i < n; i++) {
            const s = readString();
            if (sample.length < 4) sample.push(s);
          }
          return { length: n, sample };
        }
        const sz = sizes[at];
        if (!sz) throw new Error(`array type ${at}`);
        off += sz * n;
        return { length: n, skipped: true };
      }
      case 10: {
        const v = b.readBigUInt64LE(off);
        off += 8;
        return Number(v);
      }
      case 11: {
        const v = b.readBigInt64LE(off);
        off += 8;
        return Number(v);
      }
      case 12: {
        const v = b.readDoubleLE(off);
        off += 8;
        return v;
      }
      default:
        throw new Error(`type ${t} at ${off}`);
    }
  }

  for (let i = 0; i < kvCount; i++) {
    const key = readString();
    const t = readU32(b, off);
    off += 4;
    let val;
    try {
      val = readValue(t);
    } catch (e) {
      return { label, error: e.message, key, i, off, kv };
    }
    if (key.startsWith("tokenizer.")) {
      continue;
    }
    const keep =
      key.startsWith("general.") ||
      key.startsWith("clip.") ||
      key.startsWith("qwen35.") ||
      key.startsWith("llama.") ||
      key.includes("context") ||
      key.includes("projector");
    if (keep) {
      if (typeof val === "string" && val.length > 240) val = `${val.slice(0, 240)}…`;
      kv[key] = val;
    }
    if (off > b.length - 64) break;
  }
  return {
    label,
    magic: "GGUF",
    version,
    tensorCount,
    kvCount,
    parsedKeys: Object.keys(kv).length,
    kv,
    headerBytesRead: off,
  };
}

const files = [
  [
    "text-lmstudio-q4_k_m",
    "https://huggingface.co/lmstudio-community/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf?download=true",
  ],
  [
    "mmproj-lmstudio-bf16",
    "https://huggingface.co/lmstudio-community/Qwen3.5-2B-GGUF/resolve/main/mmproj-Qwen3.5-2B-BF16.gguf?download=true",
  ],
  [
    "mmproj-bartowski-f16",
    "https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF/resolve/main/mmproj-Qwen_Qwen3.5-2B-f16.gguf?download=true",
  ],
];

const results = [];
for (const [label, url] of files) {
  try {
    const { status, buf: header } = await fetchRange(url);
    console.log(label, "http", status, "got", header.length);
    const parsed = parseGguf(header, label);
    results.push(parsed);
    console.log(JSON.stringify(parsed, null, 2).slice(0, 3500));
  } catch (e) {
    console.error(label, e);
    results.push({ label, error: String(e) });
  }
}

const payload = { xcframework: { tag: "b10809", binaryBytes: buf.length, symbols }, gguf: results };
writeFileSync(`${outDir}/qwen35-gguf-metadata.json`, JSON.stringify(payload, null, 2));
console.log("wrote artifacts/qwen35-gguf-metadata.json");
