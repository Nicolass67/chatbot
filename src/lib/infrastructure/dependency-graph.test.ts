import { describe, expect, it } from "vitest";
import {
  dependencyLayers,
  dependsOn,
  startupOrder,
} from "./dependency-graph";
import { SERVICE_REGISTRY } from "./service-registry";

describe("dependency-graph", () => {
  it("searxng depends on docker (direct)", () => {
    expect(dependsOn("searxng", "docker")).toBe(true);
    expect(dependsOn("docker", "searxng")).toBe(false);
  });

  it("cloudflared depends on nextjs", () => {
    expect(dependsOn("cloudflared", "nextjs")).toBe(true);
    expect(dependsOn("nextjs", "cloudflared")).toBe(false);
  });

  it("independent services have empty deps", () => {
    expect(dependsOn("nextjs", "docker")).toBe(false);
    expect(dependsOn("lm_studio", "nextjs")).toBe(false);
  });

  it("layers place docker before searxng", () => {
    const layers = dependencyLayers(["docker", "searxng"]);
    const flat = layers.flat();
    expect(flat.indexOf("docker")).toBeLessThan(flat.indexOf("searxng"));
    expect(layers[0]).toContain("docker");
    expect(layers.some((l) => l.includes("searxng"))).toBe(true);
  });

  it("startupOrder covers all enabled registry ids once", () => {
    const order = startupOrder();
    const enabled = SERVICE_REGISTRY.filter((s) => s.enabled).map((s) => s.id);
    expect([...order].sort()).toEqual([...enabled].sort());
    expect(new Set(order).size).toBe(order.length);
    expect(order.indexOf("docker")).toBeLessThan(order.indexOf("searxng"));
    expect(order.indexOf("nextjs")).toBeLessThan(order.indexOf("cloudflared"));
  });

  it("service ids match supervisor contract", () => {
    expect(SERVICE_REGISTRY.map((s) => s.id)).toEqual([
      "docker",
      "searxng",
      "nextjs",
      "lm_studio",
      "cloudflared",
    ]);
  });
});
