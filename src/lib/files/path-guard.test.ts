import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { resolveUnderRoot } from "./path-guard";
import { FilesError } from "./types";
import { classifyRelativePathAccess, isSensitiveRelativePath } from "./access";

const tmpRoot = path.join(os.tmpdir(), `files-guard-${Date.now()}`);

afterEach(() => {
  fs.rmSync(tmpRoot, { recursive: true, force: true });
});

describe("PathGuard", () => {
  it("accepte un chemin sous la root", () => {
    fs.mkdirSync(tmpRoot, { recursive: true });
    const child = path.join(tmpRoot, "docs");
    fs.mkdirSync(child);
    const resolved = resolveUnderRoot(tmpRoot, "docs");
    expect(path.normalize(resolved).toLowerCase()).toBe(
      path.normalize(fs.realpathSync.native(child)).toLowerCase()
    );
  });

  it("refuse ..", () => {
    fs.mkdirSync(tmpRoot, { recursive: true });
    expect(() => resolveUnderRoot(tmpRoot, "../escape")).toThrow(FilesError);
  });

  it("refuse un chemin absolu en relativePath", () => {
    fs.mkdirSync(tmpRoot, { recursive: true });
    expect(() => resolveUnderRoot(tmpRoot, "C:\\Windows")).toThrow(FilesError);
  });

  it("refuse UNC", () => {
    expect(() =>
      resolveUnderRoot("\\\\server\\share", "file.txt")
    ).toThrow(FilesError);
  });
});

describe("FileAccessAxes", () => {
  it("bloque l'exposition LLM pour .env", () => {
    expect(isSensitiveRelativePath(".env")).toBe(true);
    const access = classifyRelativePathAccess(".env", { rootOk: true });
    expect(access.canAccessPath).toBe(true);
    expect(access.canExposeToLlm).toBe(false);
    expect(access.canMutate).toBe(false);
  });

  it("autorise un PDF banal", () => {
    const access = classifyRelativePathAccess("Factures/edf.pdf", {
      rootOk: true,
    });
    expect(access.canExposeToLlm).toBe(true);
    expect(access.canMutate).toBe(true);
  });
});
