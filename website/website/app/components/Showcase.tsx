import { ArrowRight } from "@phosphor-icons/react/dist/ssr";

import Reveal from "./Reveal";

export default function Showcase() {
  return (
    <section id="showcase" className="border-b border-line/60 bg-bg-deep py-24 lg:py-32">
      <div className="mx-auto max-w-[1240px] px-5 sm:px-8">
        <Reveal>
          <h2 className="max-w-[14ch] font-display text-[clamp(2.25rem,5vw,3.5rem)]">
            Raw clip in. Banger out.
          </h2>
          <p className="mt-5 max-w-[56ch] text-[17px] leading-relaxed text-muted">
            The same toolkit cuts full-length 16:9 videos, so a session can produce the
            long upload and the Short without opening a second editor.
          </p>
        </Reveal>

        <Reveal className="mt-14" delay={100}>
          <div className="grid items-center gap-8 lg:grid-cols-[minmax(0,1fr)_auto_minmax(0,0.42fr)]">
            <figure className="m-0">
              <div className="overflow-hidden rounded-panel border border-line bg-surface">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src="/shot-raw-capture.png"
                  alt="A raw 16:9 gameplay capture straight out of the recorder."
                  width={1277}
                  height={719}
                  loading="lazy"
                  decoding="async"
                  className="block w-full"
                />
              </div>
              <figcaption className="mt-3.5 text-[13px] text-faint">
                Raw 16:9 capture, straight off the recorder.
              </figcaption>
            </figure>

            <ArrowRight
              size={30}
              weight="bold"
              aria-hidden
              className="mx-auto hidden text-accent lg:block"
            />

            <figure className="m-0 mx-auto w-[62%] sm:w-[46%] lg:w-full">
              <div className="overflow-hidden rounded-panel border border-line bg-surface">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src="/shot-vertical-short.png"
                  alt="The same moment rendered as a 9:16 Short with a blurred backdrop above and below."
                  width={517}
                  height={911}
                  loading="lazy"
                  decoding="async"
                  className="block w-full"
                />
              </div>
              <figcaption className="mt-3.5 text-[13px] text-faint">
                Rendered 9:16 Short at 60 fps.
              </figcaption>
            </figure>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
