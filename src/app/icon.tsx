import { ImageResponse } from "next/og";

export const size = { width: 32, height: 32 };
export const contentType = "image/png";

export default function Icon() {
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
          borderRadius: 6,
        }}
      >
        <div
          style={{
            width: 4,
            height: 14,
            borderRadius: 2,
            background: "#5b8fd4",
          }}
        />
      </div>
    ),
    { ...size }
  );
}
