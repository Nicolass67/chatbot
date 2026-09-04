import { cn } from "@/lib/utils/cn";

type BadgeVariant = "default" | "accent" | "success" | "warning" | "error" | "muted";

interface BadgeProps {
  children: React.ReactNode;
  variant?: BadgeVariant;
  dot?: boolean;
  className?: string;
}

const variantStyles: Record<BadgeVariant, string> = {
  default: "bg-transparent text-muted border-border-subtle",
  accent: "bg-accent-muted text-accent border-transparent",
  success: "bg-transparent text-success border-success/25",
  warning: "bg-transparent text-warning border-warning/25",
  error: "bg-transparent text-error border-error/25",
  muted: "bg-transparent text-muted-foreground border-transparent",
};

export function Badge({
  children,
  variant = "default",
  dot,
  className,
}: BadgeProps) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-[var(--radius-sm)] border px-1.5 py-0.5 text-[11px] font-medium leading-none tracking-wide",
        variantStyles[variant],
        className
      )}
    >
      {dot && (
        <span
          className={cn(
            "h-1.5 w-1.5 shrink-0 rounded-full",
            variant === "success" && "bg-success",
            variant === "warning" && "bg-warning",
            variant === "error" && "bg-error",
            variant === "accent" && "bg-accent",
            (variant === "default" || variant === "muted") && "bg-muted"
          )}
          aria-hidden
        />
      )}
      {children}
    </span>
  );
}
