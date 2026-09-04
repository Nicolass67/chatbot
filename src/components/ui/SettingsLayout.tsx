import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface SettingsLayoutProps {
  title: string;
  saving?: boolean;
  children: React.ReactNode;
  backHref?: string;
}

export function SettingsLayout({
  title,
  saving,
  children,
  backHref = "/chat/new",
}: SettingsLayoutProps) {
  return (
    <div className="ambient-canvas min-h-dvh">
      <header className="glass sticky top-0 z-[var(--z-chrome)] flex mobile-chrome-header items-center gap-2 px-3 safe-top safe-x md:mx-auto md:mt-2 md:max-w-xl md:rounded-[var(--radius-2xl)]">
        <Link
          href={backHref}
          className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-muted transition-colors hover:bg-surface-hover/60 hover:text-foreground md:h-9 md:w-9"
          aria-label="Retour"
        >
          <ArrowLeft className="h-4 w-4" strokeWidth={1.75} />
        </Link>
        <h1 className="flex min-h-11 flex-1 items-center text-[15px] font-semibold tracking-[-0.02em] leading-none md:min-h-9">
          {title}
        </h1>
        {saving && (
          <span className="text-xs text-muted" aria-live="polite">
            Sauvegarde…
          </span>
        )}
      </header>
      <div className="mx-auto max-w-xl px-4 pb-20 pt-2">{children}</div>
    </div>
  );
}

interface SettingsSectionProps {
  title: string;
  description?: string;
  children: React.ReactNode;
  disabled?: boolean;
  className?: string;
}

export function SettingsSection({
  title,
  description,
  children,
  disabled,
  className,
}: SettingsSectionProps) {
  return (
    <section
      className={cn(
        "space-y-3 border-t border-border-subtle py-5 first:border-t-0 first:pt-1",
        disabled && "pointer-events-none opacity-50",
        className
      )}
    >
      <div className="max-w-md">
        <h2 className="text-[13px] font-medium tracking-[-0.01em] text-foreground">
          {title}
        </h2>
        {description && (
          <p className="mt-1 text-[12px] leading-relaxed text-muted">{description}</p>
        )}
      </div>
      <div className="space-y-4">{children}</div>
    </section>
  );
}

interface SettingsFieldProps {
  label: string;
  hint?: string;
  children: React.ReactNode;
  className?: string;
}

export function SettingsField({
  label,
  hint,
  children,
  className,
}: SettingsFieldProps) {
  return (
    <label className={cn("block space-y-1.5", className)}>
      <span className="text-[13px] text-muted">{label}</span>
      {children}
      {hint && <span className="block text-[12px] text-muted-foreground">{hint}</span>}
    </label>
  );
}

export const settingsInputClass =
  "w-full rounded-[var(--radius-md)] border border-border-subtle bg-transparent px-3 py-2 text-sm text-foreground transition-colors placeholder:text-muted-foreground hover:border-border focus:border-border-strong focus:outline-none focus-visible:outline-none";

export const settingsSelectTriggerClass =
  "w-full min-h-[40px] max-w-none justify-between rounded-[var(--radius-md)] border border-border-subtle bg-transparent px-3 py-2 text-sm text-foreground hover:border-border hover:bg-transparent hover:text-foreground";
