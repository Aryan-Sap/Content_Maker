const terms = [
  "YouTube Shorts",
  "TikTok",
  "Instagram Reels",
  "60 fps smoothing",
  "Blurred backdrop",
  "Colour grading",
  "Local render",
  "Batch queue",
];

export default function Marquee() {
  const loop = [...terms, ...terms];

  return (
    <section
      aria-hidden
      className="overflow-hidden border-b border-line/60 bg-bg-deep py-5"
    >
      <div className="cm-marquee-track flex w-max items-center gap-10 pr-10">
        {loop.map((term, index) => (
          <span key={`${term}-${index}`} className="flex items-center gap-10">
            <span className="font-display text-[15px] font-semibold tracking-[0.16em] whitespace-nowrap text-faint uppercase">
              {term}
            </span>
            <span className="h-1 w-1 rounded-full bg-accent/60" />
          </span>
        ))}
      </div>
    </section>
  );
}
