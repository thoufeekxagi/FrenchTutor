import { ImageResponse } from "next/og";

export const alt = "ParleSprint, a guided French learning path for beginners";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpenGraphImage() {
  return new ImageResponse(
    <div style={{ width: "100%", height: "100%", display: "flex", color: "#1c1e21", background: "#f8f9fa", fontFamily: "Arial, sans-serif", padding: 68 }}>
      <div style={{ width: "58%", display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 14, fontSize: 28, fontWeight: 800 }}>
          <div style={{ width: 48, height: 48, display: "flex", alignItems: "center", justifyContent: "center", borderRadius: 12, color: "white", background: "#007bff" }}>P</div>
          <span style={{ display: "flex" }}>Parle<span style={{ color: "#007bff" }}>Sprint</span></span>
        </div>
        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ color: "#007bff", fontSize: 17, fontWeight: 700, letterSpacing: 2.5, textTransform: "uppercase" }}>Guided French learning</div>
          <div style={{ maxWidth: 650, marginTop: 20, fontSize: 66, fontWeight: 800, lineHeight: .98, letterSpacing: -3 }}>Know what to practise next.</div>
          <div style={{ marginTop: 27, color: "#59626d", fontSize: 23, lineHeight: 1.4 }}>Learn, listen, write, and speak. Then train for TCF or TEF readiness.</div>
        </div>
      </div>
      <div style={{ width: "42%", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div style={{ width: 360, display: "flex", flexDirection: "column", padding: 27, border: "7px solid #1c2027", borderRadius: 28, background: "white", boxShadow: "14px 18px 0 #e5f1ff" }}>
          <div style={{ color: "#707070", fontSize: 13, fontWeight: 700, letterSpacing: 1.5 }}>TODAY · YOUR FRENCH PATH</div>
          <div style={{ marginTop: 18, fontSize: 31, fontWeight: 800, lineHeight: 1.1 }}>Your next useful step</div>
          {["Review essentials: complete", "Ask for information: now", "Speak with Marie: 5 min"].map((item, index) => <div key={item} style={{ display: "flex", padding: "15px 0", color: index === 1 ? "#007bff" : "#1c1e21", borderBottom: "1px solid #e3e7eb", fontSize: 17, fontWeight: index === 1 ? 700 : 500 }}>{item}</div>)}
        </div>
      </div>
    </div>,
    size,
  );
}
