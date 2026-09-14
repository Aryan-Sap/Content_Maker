import { Plus } from "@phosphor-icons/react/dist/ssr";

import Reveal from "./Reveal";

const questions = [
  {
    q: "Do I need FFmpeg or anything else installed?",
    a: "No. The Windows installer bundles FFmpeg, so rendering works the moment setup finishes. Download it, follow the prompts, open Content Maker.",
  },
  {
    q: "Is my footage uploaded anywhere?",
    a: "Never. Every render happens locally on your machine. The only upload is the one you ask for, when you publish a finished video to your own account.",
  },
  {
    q: "How does publishing to YouTube and TikTok work?",
    a: "Through each platform's official API. You sign in once in your browser, and refresh tokens keep later posts hands off. Instagram Reels opens the finished file for a quick manual upload instead.",
  },
  {
    q: "Can I edit normal 16:9 videos, not just Shorts?",
    a: "Yes. The timeline editor works on any canvas, so you can cut, grade and add transitions to a full-length landscape video with the same multi-track tools.",
  },
  {
    q: "Do I need an account to use it?",
    a: "No. Profiles and projects are stored only on your device. You only sign in to a platform when you choose to publish to it.",
  },
  {
    q: "What does it run on?",
    a: "Windows 10 and 11, 64-bit, through a standard installer. An Android version with native rendering is in development.",
  },
];

export default function Faq() {
  return (
    <section id="faq" className="border-b border-line/60 py-24 lg:py-32">
      <div className="mx-auto grid max-w-[1240px] gap-12 px-5 sm:px-8 lg:grid-cols-[minmax(0,0.72fr)_minmax(0,1fr)] lg:gap-20">
        <Reveal>
          <h2 className="font-display text-[clamp(2.25rem,5vw,3.5rem)]">
            Questions, answered.
          </h2>
        </Reveal>

        <Reveal delay={100}>
          <div className="border-t border-line">
            {questions.map((item) => (
              <details key={item.q} className="group border-b border-line">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-6 py-5 text-[16px] font-semibold transition-colors duration-200 hover:text-accent [&::-webkit-details-marker]:hidden">
                  {item.q}
                  <Plus
                    size={17}
                    weight="bold"
                    aria-hidden
                    className="shrink-0 text-accent transition-transform duration-300 group-open:rotate-45"
                  />
                </summary>
                <p className="max-w-[62ch] pb-6 text-[15px] leading-relaxed text-muted">
                  {item.a}
                </p>
              </details>
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  );
}
