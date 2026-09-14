import Reveal from "./Reveal";

export default function Pricing() {
  return (
    <section id="pricing" className="border-b border-line/60 py-24 lg:py-32">
      <Reveal>
        <div className="mx-auto max-w-[760px] px-5 text-center sm:px-8">
          <h2 className="font-display text-[clamp(3rem,9vw,5.5rem)]">
            Free<span className="text-accent">.</span>
          </h2>
          <p className="mx-auto mt-6 max-w-[52ch] text-[17px] leading-relaxed text-muted">
            Not a trial and not a tier. Content Maker is free to download and free to
            render with, because your GPU does the work rather than our servers.
          </p>
          <a
            href="#download"
            className="mt-9 inline-block rounded-control bg-accent px-6 py-3.5 text-[15px] font-semibold text-on-accent no-underline transition-transform duration-200 hover:-translate-y-0.5 active:translate-y-0"
          >
            Download for Windows
          </a>
        </div>
      </Reveal>
    </section>
  );
}
