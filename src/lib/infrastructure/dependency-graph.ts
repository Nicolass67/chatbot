import { SERVICE_REGISTRY } from "./service-registry";

/** Topological layers — earlier layers must be healthy before later ones are repaired. */
export function dependencyLayers(serviceIds?: string[]): string[][] {
  const defs = SERVICE_REGISTRY.filter((s) =>
    serviceIds ? serviceIds.includes(s.id) : s.enabled
  );
  const remaining = new Set(defs.map((s) => s.id));
  const layers: string[][] = [];
  const placed = new Set<string>();

  while (remaining.size > 0) {
    const layer: string[] = [];
    for (const id of remaining) {
      const def = defs.find((d) => d.id === id)!;
      const depsMet = def.dependencies.every(
        (d) => !remaining.has(d) || placed.has(d)
      );
      // Also allow if dependency isn't in the selected set
      const depsOk = def.dependencies.every(
        (d) => placed.has(d) || !defs.some((x) => x.id === d)
      );
      if (depsMet || depsOk) layer.push(id);
    }
    if (layer.length === 0) {
      // Cycle or missing — flush remaining to avoid infinite loop
      layers.push([...remaining]);
      break;
    }
    for (const id of layer) {
      remaining.delete(id);
      placed.add(id);
    }
    layers.push(layer);
  }
  return layers;
}

/** True if `dependencyId` must be healthy before repairing `serviceId`. */
export function dependsOn(serviceId: string, dependencyId: string): boolean {
  const def = SERVICE_REGISTRY.find((s) => s.id === serviceId);
  if (!def) return false;
  if (def.dependencies.includes(dependencyId)) return true;
  const queue = [...def.dependencies];
  const seen = new Set<string>();
  while (queue.length) {
    const id = queue.shift()!;
    if (seen.has(id)) continue;
    seen.add(id);
    if (id === dependencyId) return true;
    const d = SERVICE_REGISTRY.find((s) => s.id === id);
    if (d) queue.push(...d.dependencies);
  }
  return false;
}

/** Startup order (flat) respecting dependencies — parallel-safe siblings stay adjacent by layer. */
export function startupOrder(): string[] {
  return dependencyLayers().flat();
}
