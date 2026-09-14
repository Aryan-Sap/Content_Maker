import {
  Gauge,
  PaperPlaneTilt,
  Queue,
  ShieldCheck,
  SlidersHorizontal,
  Sparkle,
} from "@phosphor-icons/react/dist/ssr";

import Reveal from "./Reveal";

/** Simple Icons serves a light/dark pair, so the logos follow the page theme. */
const logo = (slug: string) => `https://cdn.simpleicons.org/${slug}/101620/f3f6fa`;

const platforms = [
  { slug: "youtube", name: "YouTube Shorts", note: "Official API" },
  { slug: "tiktok", name: "TikTok", note: "Official API" },
  { slug: "instagram", name: "Instagram Reels", note: "Manual hand-off" },
];

export default function Workflows() {
  return (
    <section id="features" className="border-b border-line/60 py-24 lg:py-32">
      <div className="mx-auto max-w-[1240px] px-5 sm:px-8">
        <Reveal>
          <p className="mb-5 text-[11px] font-semibold tracking-[0.2em] text-accent uppercase">
            Everything in the box
          </p>
          <h2 className="max-w-[18ch] font-display text-[clamp(2.25rem,5vw,3.5rem)]">
            Heavy machinery, light touch.
          </h2>
        </Reveal>

        <div className="mt-14 grid grid-cols-1 gap-4 md:grid-cols-12">
          {/* Auto render. Carries a real frame of the output format. */}
          <Reveal className="md:col-span-7" delay={0}>
            <article className="flex h-full flex-col justify-between gap-8 overflow-hidden rounded-panel border border-line bg-surface p-8 sm:flex-row sm:items-center lg:p-10">
              <div className="max-w-[34ch]">
                <Sparkle size={26} weight="duotone" className="text-accent" aria-hidden />
                <h3 className="mt-6 font-display text-[1.5rem]">Auto Shorts renderer</h3>
                <p className="mt-3 text-[15px] leading-relaxed text-muted">
                  Blurred backdrop, centred foreground, trim, audio mix and resolution
                  presets. The whole vertical format built for you in one pass.
                </p>
              </div>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/shot-vertical-short.png"
                alt="A rendered 9:16 Short with the gameplay centred over a blurred backdrop."
                width={517}
                height={911}
                loading="lazy"
                decoding="async"
                className="w-[112px] shrink-0 self-center rounded-[10px] border border-line-strong sm:w-[124px]"
              />
            </article>
          </Reveal>

          {/* Frame interpolation. Accent wash for tonal variation. */}
          <Reveal className="md:col-span-5" delay={80}>
            <article
              className="flex h-full flex-col gap-10 rounded-panel border border-line p-8 lg:p-10"
              style={{
                background:
                  "linear-gradient(150deg, color-mix(in oklab, var(--accent) 16%, var(--surface)), var(--surface) 62%)",
              }}
            >
              <div>
                <Gauge size={26} weight="duotone" className="text-accent" aria-hidden />
                <h3 className="mt-6 font-display text-[1.5rem]">60 fps interpolation</h3>
                <p className="mt-3 text-[15px] leading-relaxed text-muted">
                  Motion-interpolated smoothing turns a 30 fps capture into a 60 fps
                  Short. Choose fast, balanced or maximum quality.
                </p>
              </div>
            </article>
          </Reveal>

          {/* Timeline editor. */}
          <Reveal className="md:col-span-5" delay={0}>
            <article className="h-full rounded-panel border border-line bg-surface p-8 lg:p-10">
              <SlidersHorizontal
                size={26}
                weight="duotone"
                className="text-accent"
                aria-hidden
              />
              <h3 className="mt-6 font-display text-[1.5rem]">Manual timeline editor</h3>
              <p className="mt-3 text-[15px] leading-relaxed text-muted">
                Multi-clip, multi-track editing with trims, splits, transforms, colour
                styles, transitions and a live canvas preview. Works on a 9:16 Short or a
                full-length 16:9 video.
              </p>
            </article>
          </Reveal>

          {/* Publishing. Real platform logos, each with its real capability. */}
          <Reveal className="md:col-span-7" delay={80}>
            <article className="flex h-full flex-col justify-between gap-8 rounded-panel border border-line bg-surface p-8 lg:p-10">
              <div className="max-w-[42ch]">
                <PaperPlaneTilt
                  size={26}
                  weight="duotone"
                  className="text-accent"
                  aria-hidden
                />
                <h3 className="mt-6 font-display text-[1.5rem]">Publish without leaving</h3>
                <p className="mt-3 text-[15px] leading-relaxed text-muted">
                  Set the title, hashtags and privacy in the same panel that just rendered
                  the video, then send it. YouTube Shorts and TikTok publish through their
                  official APIs; Instagram Reels is a quick manual hand-off.
                </p>
              </div>

              <ul className="m-0 grid list-none grid-cols-1 gap-2.5 p-0 sm:grid-cols-3">
                {platforms.map((platform) => (
                  <li
                    key={platform.slug}
                    className="flex items-center gap-3 rounded-[10px] border border-line bg-bg px-3.5 py-3"
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={logo(platform.slug)}
                      alt=""
                      width={18}
                      height={18}
                      loading="lazy"
                      className="shrink-0 opacity-80"
                    />
                    <span className="min-w-0">
                      <span className="block truncate text-[13px] font-semibold">
                        {platform.name}
                      </span>
                      <span className="block text-[11.5px] text-faint">{platform.note}</span>
                    </span>
                  </li>
                ))}
              </ul>
            </article>
          </Reveal>

          {/* Batch queue. */}
          <Reveal className="md:col-span-6" delay={0}>
            <article className="h-full rounded-panel border border-line bg-surface p-8 lg:p-10">
              <Queue size={26} weight="duotone" className="text-accent" aria-hidden />
              <h3 className="mt-6 font-display text-[1.5rem]">Queue a whole folder</h3>
              <p className="mt-3 text-[15px] leading-relaxed text-muted">
                Line up a session worth of clips, apply a saved look to all of them and
                let the queue work through it while you do something else.
              </p>
            </article>
          </Reveal>

          {/* Local project studio. Tinted surface for the last cell. */}
          <Reveal className="md:col-span-6" delay={80}>
            <article className="h-full rounded-panel border border-line bg-bg-deep p-8 lg:p-10">
              <ShieldCheck size={26} weight="duotone" className="text-accent" aria-hidden />
              <h3 className="mt-6 font-display text-[1.5rem]">Your local editing studio</h3>
              <p className="mt-3 text-[15px] leading-relaxed text-muted">
                Local profiles, project library and FFmpeg rendering all live on your own
                PC. Your raw footage stays there until you choose to publish a finished
                video.
              </p>
            </article>
          </Reveal>
        </div>
      </div>
    </section>
  );
}
