"use client";

import { useCallback, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Unplug } from "lucide-react";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Spinner } from "@/components/ui/Spinner";
import type { PermissionScope } from "@/lib/policy";
import type { OAuthAccountPublic } from "@/lib/integrations/oauth/types";
import {
  disconnectGmail,
  fetchOAuthAccounts,
  EmailApiError,
} from "@/lib/email/email-client";
import { openGmailOAuthStart } from "@/lib/native/open-external";

const PERMISSION_LABELS: Partial<Record<PermissionScope, string>> = {
  READ_EMAIL: "Lecture",
  SEARCH_EMAIL: "Recherche",
  ANALYZE_EMAIL: "Analyse",
  CREATE_DRAFT: "Brouillons",
  SEND_EMAIL: "Envoi",
  TRASH_EMAIL: "Corbeille",
};

function formatGmailCallbackReason(reason: string): string {
  switch (reason) {
    case "access_denied":
      return "Autorisation refusée dans Google.";
    case "invalid_state":
      return "Session OAuth expirée — réessayez.";
    case "config_error":
      return "Configuration OAuth incomplète côté serveur.";
    case "exchange_failed":
      return "Échec de l'échange de tokens avec Google.";
    case "missing_code_or_state":
      return "Réponse OAuth incomplète.";
    default:
      return reason;
  }
}

export function EmailOAuthPanel() {
  const searchParams = useSearchParams();
  const [loading, setLoading] = useState(true);
  const [configured, setConfigured] = useState(false);
  const [accounts, setAccounts] = useState<OAuthAccountPublic[]>([]);
  const [redirectUri, setRedirectUri] = useState<string | null>(null);
  const [disconnecting, setDisconnecting] = useState(false);
  const [banner, setBanner] = useState<{
    type: "success" | "error";
    message: string;
  } | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const data = await fetchOAuthAccounts();
      setConfigured(data.configured);
      setAccounts(data.accounts);
      setRedirectUri(data.redirectUri ?? null);
    } catch (error) {
      setBanner({
        type: "error",
        message:
          error instanceof EmailApiError
            ? error.message
            : "Impossible de charger les comptes Gmail",
      });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const gmail = searchParams.get("gmail");
    const reason = searchParams.get("reason");
    if (gmail === "connected") {
      setBanner({
        type: "success",
        message: "Gmail connecté avec succès.",
      });
      void load();
    } else if (gmail === "error") {
      setBanner({
        type: "error",
        message: formatGmailCallbackReason(reason ?? "unknown"),
      });
    }
  }, [searchParams, load]);

  const handleDisconnect = async () => {
    setDisconnecting(true);
    try {
      await disconnectGmail();
      await load();
      setBanner({ type: "success", message: "Gmail déconnecté." });
    } catch (error) {
      setBanner({
        type: "error",
        message:
          error instanceof EmailApiError
            ? error.message
            : "Échec de la déconnexion",
      });
    } finally {
      setDisconnecting(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center gap-2 py-8 text-muted">
        <Spinner />
        <span className="text-sm">Chargement…</span>
      </div>
    );
  }

  if (!configured) {
    return (
      <div className="border-t border-border-subtle py-1">
        <p className="text-[13px] text-muted">
          L&apos;intégration Gmail n&apos;est pas configurée sur ce serveur
          (variables OAuth manquantes).
        </p>
      </div>
    );
  }

  const account = accounts[0];

  return (
    <div className="space-y-4">
      {banner && (
        <div
          className={`rounded-[var(--radius-md)] border px-3 py-2 text-sm ${
            banner.type === "success"
              ? "border-success/30 bg-success-muted/40 text-success"
              : "border-error/30 bg-error-muted/40 text-error"
          }`}
          role="alert"
        >
          {banner.message}
        </div>
      )}

      {account ? (
        <div className="space-y-3 border-t border-border-subtle py-1">
          <div className="mb-3 flex items-start justify-between gap-3">
            <div>
              <p className="text-[13px] font-medium text-foreground">
                {account.accountEmail}
              </p>
              <p className="text-[12px] text-muted">Compte Gmail connecté</p>
            </div>
            <Badge variant="success" dot>
              Connecté
            </Badge>
          </div>

          <div className="mb-4">
            <p className="mb-1.5 text-xs font-medium text-muted-foreground">
              Permissions accordées
            </p>
            <div className="flex flex-wrap gap-1.5">
              {account.grantedPermissions.map((permission) => (
                <Badge key={permission} variant="default">
                  {PERMISSION_LABELS[permission] ?? permission}
                </Badge>
              ))}
            </div>
            {!account.grantedPermissions.includes("TRASH_EMAIL") && (
              <p className="mt-2 text-xs text-amber-600">
                Permission Corbeille absente —{" "}
                <a
                  href="/api/oauth/gmail/start"
                  className="underline"
                  onClick={(event) => {
                    event.preventDefault();
                    void openGmailOAuthStart();
                  }}
                >
                  reconnectez Gmail
                </a>{" "}
                pour autoriser la suppression depuis l&apos;assistant.
              </p>
            )}
          </div>

          <Button
            type="button"
            variant="danger"
            size="sm"
            loading={disconnecting}
            onClick={() => void handleDisconnect()}
          >
            <Unplug className="h-3.5 w-3.5" />
            Déconnecter Gmail
          </Button>
        </div>
      ) : (
        <div className="space-y-3 border-t border-border-subtle py-1">
          <p className="text-[13px] text-muted">
            Aucun compte Gmail connecté. Autorisez l&apos;accès pour lire vos
            emails et envoyer des brouillons depuis le chat.
          </p>
          <a
            href="/api/oauth/gmail/start"
            onClick={(event) => {
              event.preventDefault();
              void openGmailOAuthStart();
            }}
          >
            <Button type="button" variant="primary" size="md">
              Connecter Gmail
            </Button>
          </a>
          {redirectUri ? (
            <div className="rounded-[var(--radius-md)] border border-border-subtle bg-surface/40 p-3 text-[12px] text-muted">
              <p className="mb-1 font-medium text-foreground">
                Si Google affiche redirect_uri_mismatch
              </p>
              <p className="mb-2">
                Dans Google Cloud → APIs &amp; Services → Credentials → ton
                client OAuth <strong>Web</strong>, ajoute exactement cette URI
                autorisée :
              </p>
              <code className="block break-all rounded bg-surface-elevated px-2 py-1.5 text-[11px] text-foreground">
                {redirectUri}
              </code>
            </div>
          ) : null}
        </div>
      )}
    </div>
  );
}
