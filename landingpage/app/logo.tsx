import Image from "next/image";

export function LogoMark({ size = 32 }: { size?: number }) {
  return (
    <Image
      src="/icon-512.png"
      width={size}
      height={size}
      alt=""
      aria-hidden="true"
      className="shrink-0"
    />
  );
}

export function Logo({ size = 32 }: { size?: number }) {
  return (
    <span className="flex items-center gap-2">
      <LogoMark size={size} />
      <span className="brand-wordmark">ParleSprint</span>
    </span>
  );
}
