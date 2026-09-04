import type { RouteDecision } from "@/lib/request-router/types";
import {
  createFreshnessStateFromRoute,
  type FreshnessState,
} from "./freshness-policy";
import {
  createResearchFlowStateFromRoute,
  type ResearchFlowState,
} from "./research-flow";

export { createFreshnessStateFromRoute, createResearchFlowStateFromRoute };

export function createResearchFlowState(
  route: RouteDecision,
  userGoal: string
): ResearchFlowState {
  return createResearchFlowStateFromRoute(route, userGoal);
}

/** @deprecated Utiliser createResearchFlowStateFromRoute */
export function createMarketDiscoveryStateFromRoute(
  route: RouteDecision,
  userGoal: string
): ResearchFlowState {
  return createResearchFlowStateFromRoute(route, userGoal);
}

export type AgentRouteState = {
  freshness: FreshnessState;
  research: ResearchFlowState;
};

export function buildAgentRouteState(
  route: RouteDecision,
  userGoal: string,
  webSearchEnabled: boolean
): AgentRouteState {
  return {
    freshness: createFreshnessStateFromRoute(route, webSearchEnabled),
    research: createResearchFlowStateFromRoute(route, userGoal),
  };
}
