import { ImageResponse } from "next/og";

export const alt = "ParleSprint — personalized French practice that connects every skill";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpenGraphImage() {
  return new ImageResponse(
    <div style={{ width: "100%", height: "100%", display: "flex", color: "#1b2a4a", background: "#faf9f6", fontFamily: "Georgia, serif", padding: 68 }}>
      <div style={{ width: "58%", display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 14, fontFamily: "Arial, sans-serif", fontSize: 28, fontWeight: 800 }}>
          <div style={{ width: 48, height: 48, display: "flex", alignItems: "center", justifyContent: "center", borderRadius: 10, color: "white", background: "#c8433e" }}>P</div>
          <span style={{ display: "flex" }}>Parle<span style={{ color: "#c8433e" }}>Sprint</span></span>
        </div>
        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ color: "#c8433e", fontFamily: "monospace", fontSize: 17, letterSpacing: 3, textTransform: "uppercase" }}>Personalized French practice</div>
          <div style={{ maxWidth: 680, marginTop: 20, fontSize: 69, lineHeight: .96, letterSpacing: -3 }}>Turn French practice into real progress.</div>
          <div style={{ marginTop: 27, color: "#606c80", fontFamily: "Arial, sans-serif", fontSize: 24, lineHeight: 1.4 }}>Vocabulary, grammar, listening, writing, and live speaking—connected by feedback.</div>
        </div>
      </div>
      <div style={{ width: "42%", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div style={{ width: 360, display: "flex", flexDirection: "column", padding: 28, border: "7px solid #1b2a4a", borderRadius: 28, background: "white", boxShadow: "12px 16px 0 #edf1f7" }}>
          <div style={{ color: "#606c80", fontFamily: "monospace", fontSize: 14 }}>TODAY’S PATH · 14 MIN</div>
          <div style={{ marginTop: 22, fontSize: 33 }}>Build it. Hear it. Use it.</div>
          {["Vocabulary — complete", "Grammar — now", "Read & listen", "Writing", "Speak with Marie"].map((item, index) => <div key={item} style={{ display: "flex", padding: "15px 0", color: index === 1 ? "#c8433e" : "#1b2a4a", borderBottom: "1px solid #dce2eb", fontFamily: "Arial, sans-serif", fontSize: 18 }}>{item}</div>)}
        </div>
      </div>
    </div>,
    size,
  );
}
