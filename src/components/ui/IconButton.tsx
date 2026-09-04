import { forwardRef, type ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/utils/cn";
import { Spinner } from "@/components/ui/Spinner";

export type IconButtonVariant = "ghost" | "subtle" | "primary" | "danger";
export type IconButtonSize = "sm" | "md" | "lg";

interface IconButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: IconButtonVariant;
  size?: IconButtonSize;
  loading?: boolean;
  label: string;
}

const variantStyles: Record<IconButtonVariant, string> = {
  ghost: "text-muted hover:bg-surface-hover hover:text-foreground",
  subtle:
    "bg-surface-elevated text-foreground border border-border-strong hover:bg-surface-hover",
  primary:
    "bg-accent text-accent-foreground hover:bg-accent-hover shadow-[0_0_0_1px_color-mix(in_srgb,var(--accent)_40%,transparent)]",
  danger: "bg-error text-foreground hover:brightness-110",
};

/* Desktop sizes; on mobile bump to ≥44pt for primary chrome controls */
const sizeStyles: Record<IconButtonSize, string> = {
  sm: "h-8 w-8 rounded-[var(--radius-md)] max-md:h-11 max-md:w-11",
  md: "h-9 w-9 rounded-[var(--radius-md)] max-md:h-11 max-md:w-11",
  lg: "h-10 w-10 rounded-[var(--radius-md)] max-md:h-11 max-md:w-11",
};

export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(
  function IconButton(
    {
      className,
      variant = "ghost",
      size = "md",
      loading,
      disabled,
      label,
      children,
      ...props
    },
    ref
  ) {
    return (
      <button
        ref={ref}
        type="button"
        aria-label={label}
        title={label}
        disabled={disabled || loading}
        className={cn(
          "inline-flex shrink-0 items-center justify-center transition-[background-color,color,transform] duration-[var(--duration-fast)] focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50 active:scale-[0.96]",
          variantStyles[variant],
          sizeStyles[size],
          className
        )}
        {...props}
      >
        {loading ? <Spinner size="sm" /> : children}
      </button>
    );
  }
);
