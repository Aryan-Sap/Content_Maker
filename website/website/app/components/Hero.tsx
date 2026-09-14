import { WindowsLogo } from "@phosphor-icons/react/dist/ssr";

import Reveal from "./Reveal";

export default function Hero() {
  return (
    <section id="top" className="relative overflow-clip border-b border-line/60">
      {/* Single soft accent wash behind the composition. Same hue as the
          CTA, kept low-opacity so it reads as depth, not as a gradient. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-40 -right-24 h-[560px] w-[560px] rounded-full opacity-[0.16] blur-[110px]"
        style={{ background: "radial-gradient(circle, var(--accent), transparent 70%)" }}
      />

      <div className="relative mx-auto grid max-w-[1240px] items-center gap-14 px-5 pt-16 pb-20 sm:px-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)] lg:gap-16 lg:pt-24 lg:pb-28">
        <Reveal>
          <p className="mb-5 text-[11px] font-semibold tracking-[0.2em] text-accent uppercase">
            Free for Windows 10 and 11
          </p>

          <h1 className="font-display text-[clamp(2.75rem,6vw,4.5rem)]">
            Make Content
            <br />
            Easy<span className="text-accent">.</span>
          </h1>

          <p className="mt-6 max-w-[46ch] text-[17px] leading-relaxed text-muted">
            Start a local project, drop in raw gameplay, and get a polished 60 fps
            vertical Short—rendered on your PC and ready to publish to your channel.
          </p>

          <div className="mt-9 flex flex-wrap items-center gap-3">
            <a
              href="#download"
              className="inline-flex items-center gap-2.5 rounded-control bg-accent px-6 py-3.5 text-[15px] font-semibold text-on-accent no-underline transition-transform duration-200 hover:-translate-y-0.5 active:translate-y-0"
            >
              <WindowsLogo size={19} weight="fill" aria-hidden />
              Download for Windows
            </a>
            <a
              href="#how"
              className="rounded-control border border-line-strong px-6 py-3.5 text-[15px] font-semibold text-ink no-underline transition-colors duration-200 hover:border-accent hover:text-accent"
            >
              See how it works
            </a>
          </div>
        </Reveal>

        <Reveal delay={120}>
          <figure className="m-0">
            <div className="overflow-hidden rounded-panel border border-line bg-surface shadow-[var(--shadow-panel)]">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/app-workspace.png"
                alt="The Content Maker workspace on Windows, showing the project list and the choice of starting workflow."
                width={1920}
                height={1002}
                fetchPriority="high"
                decoding="async"
                className="block w-full"
              />
            </div>
            <figcaption className="mt-3.5 text-[13px] text-faint">
              Your local studio. Start an Auto Render project or open a Custom Timeline,
              then edit, render and publish without leaving it.
            </figcaption>
          </figure>
        </Reveal>
      </div>
    </section>
  );
}
