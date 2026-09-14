import { WindowsLogo } from "@phosphor-icons/react/dist/ssr";

import Reveal from "./Reveal";

export default function DownloadCta() {
  return (
    <section id="download" className="relative overflow-clip bg-bg-deep py-24 lg:py-32">
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-56 left-1/2 h-[540px] w-[820px] -translate-x-1/2 rounded-full opacity-[0.14] blur-[120px]"
        style={{ background: "radial-gradient(circle, var(--accent), transparent 70%)" }}
      />

      <Reveal>
        <div className="relative mx-auto max-w-[860px] px-5 text-center sm:px-8">
          <h2 className="font-display text-[clamp(2.5rem,6.5vw,4.5rem)]">
            Your next Short is one click away.
          </h2>

          <div className="mt-10 flex flex-wrap justify-center gap-3">
            <a
              href="/downloads/ContentMakerSetup.exe"
              className="inline-flex items-center gap-2.5 rounded-control bg-accent px-7 py-4 text-[15px] font-semibold text-on-accent no-underline transition-transform duration-200 hover:-translate-y-0.5 active:translate-y-0"
            >
              <WindowsLogo size={19} weight="fill" aria-hidden />
              Download for Windows
            </a>
            <span className="inline-flex items-center rounded-control border border-line-strong px-7 py-4 text-[15px] font-semibold text-faint">
              Android in development
            </span>
          </div>

          <p className="mt-7 text-[13.5px] text-faint">
            Windows 10 and 11, 64-bit. FFmpeg is included in the installer.
          </p>
        </div>
      </Reveal>
    </section>
  );
}
