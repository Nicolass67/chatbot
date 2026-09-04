import { ImageResponse } from "next/og";

function AppIcon({ size }: { size: number }) {
  const radius = Math.round(size * 0.18);
  const barWidth = Math.max(3, Math.round(size * 0.1));
  const barHeight = Math.round(size * 0.42);

  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "#18181a",
        borderRadius: radius,
      }}
    >
      <div
        style={{
          width: barWidth,
          height: barHeight,
          borderRadius: Math.round(barWidth / 2),
          background: "#5b8fd4",
        }}
      />
    </div>
  );
}

export function renderAppIcon(size: number) {
  return new ImageResponse(<AppIcon size={size} />, {
    width: size,
    height: size,
  });
}
