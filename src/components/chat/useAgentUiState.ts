import { useCallback, useReducer } from "react";
import type { OrchestratorEvent } from "@/lib/agent/events";
import {
  createInitialAgentUiState,
  reduceAgentUiState,
  type AgentUiState,
} from "./agent-ui-state";

export function useAgentUiState(): {
  agentUi: AgentUiState;
  handleAgentEvent: (event: OrchestratorEvent) => void;
  resetAgentUi: () => void;
} {
  const [agentUi, dispatch] = useReducer(
    reduceAgentUiState,
    undefined,
    createInitialAgentUiState
  );

  const handleAgentEvent = useCallback((event: OrchestratorEvent) => {
    dispatch(event);
  }, []);

  const resetAgentUi = useCallback(() => {
    dispatch({ type: "__reset__" });
  }, []);

  return { agentUi, handleAgentEvent, resetAgentUi };
}

export type { AgentUiState };
