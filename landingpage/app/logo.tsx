export function LogoMark({ size = 32 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 1024 1024"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
      className="shrink-0"
    >
      <defs>
        <linearGradient id="ps-mark-bg" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#1A8CFF" />
          <stop offset="100%" stopColor="#0062CC" />
        </linearGradient>
      </defs>
      <rect width="1024" height="1024" rx="224" fill="url(#ps-mark-bg)" />
      <path
        d="M 330 236 L 570 236 C 692 236 770 314 770 430 C 770 546 692 624 570 624 L 452 624 L 452 788 L 330 788 Z M 452 344 L 452 516 L 560 516 C 614 516 646 484 646 430 C 646 376 614 344 560 344 Z"
        fill="#FFFFFF"
      />
      <path
        d="M 560 600 L 700 600 L 636 708 L 730 708 L 540 940 L 596 768 L 508 768 Z"
        fill="#FFFFFF"
        stroke="#0062CC"
        strokeWidth="26"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function Logo({ size = 32 }: { size?: number }) {
  return (
    <span className="flex items-center gap-2">
      <LogoMark size={size} />
      <span className="font-bold text-xl tracking-tight text-[#1C1E21]">
        Parle<span className="text-[#007BFF]">Sprint</span>
      </span>
    </span>
  );
}
