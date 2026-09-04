import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#18181a",
          borderRadius: 36,
        }}
      >
        <div
          style={{
            width: 18,
            height: 64,
            borderRadius: 9,
            background: "#5b8fd4",
          }}
        />
      </div>
    ),
    { ...size }
  );
}
