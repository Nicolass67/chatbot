/** Page HTML servie par le Worker quand Next.js est indisponible (PC éteint). */
export function renderOfflineWakePage(): string {
  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta name="theme-color" content="#18181a" />
  <meta name="color-scheme" content="dark" />
  <title>Chatbot — PC hors ligne</title>
  <style>
    :root {
      --background: #18181a;
      --foreground: #e2e2e6;
      --surface: #232326;
      --surface-elevated: #2a2a2e;
      --surface-hover: #313135;
      --border: #3d3d43;
      --border-subtle: rgba(255, 255, 255, 0.065);
      --border-strong: #505057;
      --accent: #5b8fd4;
      --accent-hover: #74a3e0;
      --accent-subtle: rgba(91, 143, 212, 0.08);
      --accent-muted: rgba(91, 143, 212, 0.14);
      --muted: #a3a3aa;
      --muted-foreground: #74747c;
      --success: #6baf8c;
      --warning: #c9a06c;
      --error: #c97d79;
      --radius-md: 0.5625rem;
      --radius-lg: 0.75rem;
      --radius-xl: 0.9375rem;
      --radius-2xl: 1.125rem;
      --glass-blur: 20px;
      --ease-out: cubic-bezier(0.22, 1, 0.36, 1);
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      min-height: 100%;
      min-height: 100dvh;
      background: var(--background);
      color: var(--foreground);
      font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    body {
      display: flex;
      align-items: center;
      justify-content: center;
      padding:
        max(1.5rem, env(safe-area-inset-top))
        max(1.25rem, env(safe-area-inset-right))
        max(1.5rem, env(safe-area-inset-bottom))
        max(1.25rem, env(safe-area-inset-left));
      background-color: var(--background);
      background-image:
        radial-gradient(
          ellipse 95% 58% at 0% -5%,
          rgba(91, 143, 212, 0.28),
          transparent 58%
        ),
        radial-gradient(
          ellipse 70% 48% at 100% 105%,
          rgba(168, 180, 200, 0.12),
          transparent 52%
        ),
        radial-gradient(
          ellipse 50% 36% at 68% 22%,
          rgba(91, 143, 212, 0.1),
          transparent 68%
        );
      background-attachment: fixed;
    }
    .shell {
      width: 100%;
      max-width: 24rem;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      margin-bottom: 1.25rem;
      padding: 0 0.15rem;
    }
    .brand-mark {
      width: 3px;
      height: 1rem;
      border-radius: 999px;
      background: var(--accent);
      flex-shrink: 0;
    }
    .brand-name {
      font-size: 0.9375rem;
      font-weight: 600;
      letter-spacing: -0.02em;
    }
    .panel {
      width: 100%;
      background: color-mix(in srgb, var(--surface-elevated) 36%, transparent);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-2xl);
      box-shadow:
        0 0 0 0.5px rgba(255, 255, 255, 0.06) inset,
        0 12px 36px rgb(0 0 0 / 0.32);
      backdrop-filter: blur(var(--glass-blur)) saturate(1.45);
      -webkit-backdrop-filter: blur(var(--glass-blur)) saturate(1.45);
      padding: 1.5rem 1.35rem 1.35rem;
    }
    @supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
      .panel { background: var(--surface); }
    }
    .status-row {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      margin-bottom: 1.15rem;
      font-size: 0.6875rem;
      font-weight: 500;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--warning);
    }
    .status-dot {
      width: 0.4rem;
      height: 0.4rem;
      border-radius: 50%;
      background: var(--warning);
      flex-shrink: 0;
      animation: pulse 2s ease-in-out infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.4; }
    }
    h1 {
      font-size: 1.25rem;
      font-weight: 600;
      letter-spacing: -0.02em;
      margin: 0 0 0.45rem;
      line-height: 1.3;
    }
    .lead {
      margin: 0 0 1.35rem;
      color: var(--muted);
      font-size: 0.875rem;
      line-height: 1.55;
    }
    .actions {
      display: flex;
      flex-direction: column;
      gap: 0.55rem;
    }
    .btn {
      appearance: none;
      width: 100%;
      border: none;
      border-radius: var(--radius-lg);
      padding: 0.8rem 1.1rem;
      font-size: 0.9375rem;
      font-weight: 600;
      letter-spacing: -0.01em;
      cursor: pointer;
      transition:
        background-color 140ms var(--ease-out),
        border-color 140ms var(--ease-out),
        color 140ms var(--ease-out),
        transform 120ms var(--ease-out),
        opacity 120ms var(--ease-out);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 0.5rem;
      min-height: 2.75rem;
      color: var(--accent-foreground, #eef3fa);
      background: var(--accent);
      box-shadow: 0 0 0 1px color-mix(in srgb, var(--accent) 40%, transparent);
    }
    .btn:hover:not(:disabled) { background: var(--accent-hover); }
    .btn:active:not(:disabled) { transform: scale(0.98); }
    .btn:disabled { opacity: 0.55; cursor: wait; }
    .btn-secondary {
      color: var(--foreground);
      background: color-mix(in srgb, var(--surface) 55%, transparent);
      border: 1px solid var(--border-subtle);
      box-shadow: none;
    }
    .btn-secondary:hover:not(:disabled) {
      background: var(--surface-hover);
      border-color: var(--border);
    }
    .btn-danger {
      color: var(--error);
      background: color-mix(in srgb, var(--error) 10%, transparent);
      border: 1px solid color-mix(in srgb, var(--error) 28%, transparent);
      box-shadow: none;
    }
    .btn-danger:hover:not(:disabled) {
      background: color-mix(in srgb, var(--error) 16%, transparent);
      border-color: color-mix(in srgb, var(--error) 45%, transparent);
    }
    .btn-spinner {
      width: 1rem;
      height: 1rem;
      border: 2px solid color-mix(in srgb, currentColor 28%, transparent);
      border-top-color: currentColor;
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
      display: none;
      flex-shrink: 0;
    }
    .btn.loading .btn-spinner { display: block; }
    .btn.loading .btn-label { opacity: 0.9; }
    @keyframes spin { to { transform: rotate(360deg); } }
    .feedback {
      margin-top: 1rem;
      padding: 0.8rem 0.9rem;
      border-radius: var(--radius-lg);
      font-size: 0.8125rem;
      line-height: 1.5;
      display: none;
    }
    .feedback.visible { display: block; }
    .feedback.info {
      color: var(--muted);
      background: color-mix(in srgb, var(--surface) 70%, transparent);
      border: 1px solid var(--border-subtle);
    }
    .feedback.success {
      color: var(--success);
      background: color-mix(in srgb, var(--success) 10%, transparent);
      border: 1px solid color-mix(in srgb, var(--success) 25%, transparent);
    }
    .feedback.error {
      color: var(--error);
      background: color-mix(in srgb, var(--error) 10%, transparent);
      border: 1px solid color-mix(in srgb, var(--error) 25%, transparent);
    }
    .feedback-title { font-weight: 600; margin-bottom: 0.2rem; }
    .feedback-detail {
      font-size: 0.75rem;
      opacity: 0.92;
      word-break: break-word;
      color: inherit;
    }
    .footer {
      margin-top: 1.1rem;
      padding-top: 1rem;
      border-top: 1px solid var(--border-subtle);
      font-size: 0.6875rem;
      color: var(--muted-foreground);
      text-align: center;
      line-height: 1.5;
      letter-spacing: 0.01em;
    }
  </style>
</head>
<body>
  <div class="shell">
    <div class="brand">
      <span class="brand-mark" aria-hidden="true"></span>
      <span class="brand-name">Chatbot</span>
    </div>
    <main class="panel">
      <div class="status-row">
        <span class="status-dot" aria-hidden="true"></span>
        PC hors ligne
      </div>
      <h1>Réveiller ou relancer</h1>
      <p class="lead">
        Le chatbot local ne répond pas. Allume le PC à distance, ou relance les services si la machine est déjà allumée.
      </p>
      <div class="actions">
        <button type="button" class="btn" id="wake-btn">
          <span class="btn-spinner" id="wake-spinner"></span>
          <span class="btn-label" id="wake-label">Allumer le PC</span>
        </button>
        <button type="button" class="btn btn-secondary" id="services-btn">
          <span class="btn-spinner" id="services-spinner"></span>
          <span class="btn-label" id="services-label">Démarrer les services</span>
        </button>
        <button type="button" class="btn btn-danger" id="shutdown-btn">
          <span class="btn-spinner" id="shutdown-spinner"></span>
          <span class="btn-label" id="shutdown-label">Éteindre le PC</span>
        </button>
      </div>
      <div class="feedback info" id="status-box" role="status" aria-live="polite"></div>
      <p class="footer">Worker · Freebox WoL · Démarrage à distance</p>
    </main>
  </div>
  <script>
    (function () {
      var wakeBtn = document.getElementById("wake-btn");
      var servicesBtn = document.getElementById("services-btn");
      var shutdownBtn = document.getElementById("shutdown-btn");
      var statusBox = document.getElementById("status-box");
      var pollTimer = null;
      var shutdownConfirm = false;
      var shutdownConfirmTimer = null;

      function setStatus(kind, title, detail) {
        statusBox.className = "feedback visible " + kind;
        statusBox.innerHTML =
          '<div class="feedback-title">' + title + "</div>" +
          (detail ? '<div class="feedback-detail">' + detail + "</div>" : "");
      }

      function setButtonLoading(btn, loading) {
        btn.disabled = loading;
        btn.classList.toggle("loading", loading);
      }

      function setAllLoading(loading) {
        setButtonLoading(wakeBtn, loading);
        setButtonLoading(servicesBtn, loading);
        setButtonLoading(shutdownBtn, loading);
      }

      function resetShutdownConfirm() {
        shutdownConfirm = false;
        if (shutdownConfirmTimer) {
          clearTimeout(shutdownConfirmTimer);
          shutdownConfirmTimer = null;
        }
        document.getElementById("shutdown-label").textContent = "Éteindre le PC";
      }

      function formatError(data) {
        if (data.message) return data.message;
        if (data.msg) return data.msg;
        if (data.error_code) return "Code Freebox : " + data.error_code;
        if (data.error) return data.error;
        return "La requête n'a pas abouti.";
      }

      function startPolling(statusTitle) {
        if (pollTimer) return;
        var attempts = 0;
        pollTimer = setInterval(function () {
          attempts += 1;
          fetch("/status", { cache: "no-store" })
            .then(function (r) { return r.json(); })
            .then(function (data) {
              if (data.backend === "online") {
                clearInterval(pollTimer);
                pollTimer = null;
                setStatus("success", "Chatbot en ligne", "Redirection vers le chatbot…");
                window.location.href = "/";
                return;
              }
              setStatus(
                "info",
                statusTitle,
                "Vérification " + attempts + " — cela peut prendre 1 à 3 minutes."
              );
            })
            .catch(function () {
              setStatus("info", statusTitle, "En attente de connexion au PC…");
            });
        }, 5000);
      }

      wakeBtn.addEventListener("click", function () {
        setAllLoading(true);
        setStatus("info", "Envoi en cours…", "Contact de la Freebox pour Wake-on-LAN.");

        fetch("/wake", { method: "POST" })
          .then(function (response) {
            return response.json().then(function (data) {
              return { status: response.status, data: data };
            });
          })
          .then(function (result) {
            if (result.data.ok) {
              setStatus(
                "success",
                "Signal envoyé",
                result.data.message || "Wake-on-LAN transmis à la Freebox."
              );
              startPolling("Démarrage du PC…");
              return;
            }
            setStatus("error", "Échec du réveil", formatError(result.data));
          })
          .catch(function () {
            setStatus("error", "Erreur réseau", "Impossible de joindre le Worker.");
          })
          .finally(function () {
            setAllLoading(false);
          });
      });

      servicesBtn.addEventListener("click", function () {
        setAllLoading(true);
        setStatus(
          "info",
          "Démarrage en cours…",
          "Demande enregistrée — le PC allumé lance la stack (~1 min)."
        );

        fetch("/start-services", { method: "POST" })
          .then(function (response) {
            return response.json().then(function (data) {
              return { status: response.status, data: data };
            });
          })
          .then(function (result) {
            if (result.data.ok) {
              setStatus(
                "success",
                "Demande de démarrage envoyée",
                result.data.message ||
                  "Le PC va démarrer les services Chatbot."
              );
              startPolling("Démarrage des services…");
              return;
            }
            setStatus("error", "Échec", formatError(result.data));
          })
          .catch(function () {
            setStatus("error", "Erreur réseau", "Impossible de joindre le Worker.");
          })
          .finally(function () {
            setAllLoading(false);
          });
      });

      shutdownBtn.addEventListener("click", function () {
        if (!shutdownConfirm) {
          resetShutdownConfirm();
          shutdownConfirm = true;
          document.getElementById("shutdown-label").textContent =
            "Confirmer l'arrêt du PC";
          setStatus(
            "error",
            "Confirmation requise",
            "Appuyez à nouveau pour éteindre le PC dans ~60 secondes."
          );
          shutdownConfirmTimer = setTimeout(resetShutdownConfirm, 8000);
          return;
        }

        resetShutdownConfirm();
        setAllLoading(true);
        setStatus(
          "info",
          "Arrêt en cours…",
          "Arrêt propre des services puis extinction Windows."
        );

        fetch("/shutdown-pc", { method: "POST" })
          .then(function (response) {
            return response.json().then(function (data) {
              return { status: response.status, data: data };
            });
          })
          .then(function (result) {
            if (result.data.ok) {
              setStatus(
                "success",
                "Extinction planifiée",
                result.data.message ||
                  "Le PC s'éteindra sous environ une minute."
              );
              return;
            }
            setStatus("error", "Échec", formatError(result.data));
          })
          .catch(function () {
            setStatus("error", "Erreur réseau", "Impossible de joindre le Worker.");
          })
          .finally(function () {
            setAllLoading(false);
          });
      });
    })();
  </script>
</body>
</html>`;
}

export function offlineWakePageResponse(): Response {
  return new Response(renderOfflineWakePage(), {
    status: 503,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}
