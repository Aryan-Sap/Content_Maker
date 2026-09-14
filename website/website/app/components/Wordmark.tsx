type WordmarkProps = {
  /** Diameter of the ring mark in pixels. */
  size?: number;
  showText?: boolean;
};

/**
 * The Content Maker mark: a ring with an M inside, matching the
 * BrandLogo painter used across the desktop app.
 */
export default function Wordmark({ size = 30, showText = true }: WordmarkProps) {
  return (
    <span className="inline-flex items-center gap-2.5">
      <svg
        width={size}
        height={size}
        viewBox="0 0 32 32"
        role="img"
        aria-label="Content Maker"
        className="shrink-0"
      >
        <circle cx="16" cy="16" r="14.5" fill="none" stroke="var(--accent)" strokeWidth="2.4" />
        <path
          d="M9.6 22V10.6l6.4 7.2 6.4-7.2V22"
          fill="none"
          stroke="var(--text)"
          strokeWidth="2.4"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
      {showText ? (
        <span className="font-display text-[15px] font-bold tracking-[0.14em] whitespace-nowrap uppercase">
          Content Maker
        </span>
      ) : null}
    </span>
  );
}
