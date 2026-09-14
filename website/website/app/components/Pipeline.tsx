import Reveal from "./Reveal";

const steps = [
  {
    ordinal: "01",
    title: "Start a local project",
    body: "Choose Auto Render for a fast social export, or open the Custom Timeline when your edit needs more control. Your projects stay on your PC.",
  },
  {
    ordinal: "02",
    title: "Drop in your gameplay",
    body: "Add a single clip or queue a session. Trim the moment that matters, apply a saved look, then render it your way.",
  },
  {
    ordinal: "03",
    title: "Render and publish",
    body: "Create a crisp 60 fps vertical export with a blurred backdrop, then send it to YouTube Shorts or TikTok through their official APIs.",
  },
];

export default function Pipeline() {
  return (
    <section id="how" className="border-b border-line/60 py-24 lg:py-32">
      <div className="mx-auto max-w-[1240px] px-5 sm:px-8">
        <Reveal>
          <h2 className="max-w-[16ch] font-display text-[clamp(2.25rem,5vw,3.5rem)]">
            Start to posted in three moves.
          </h2>
          <p className="mt-5 max-w-[52ch] text-[17px] leading-relaxed text-muted">
            No timeline required. But when you want one, a full multi-track editor is
            waiting in the same workspace.
          </p>
        </Reveal>

        <ol className="mt-16 grid list-none grid-cols-1 gap-px overflow-hidden rounded-panel border border-line bg-line p-0 md:grid-cols-[1.15fr_1fr_1fr]">
          {steps.map((step, index) => (
            <li key={step.ordinal} className="bg-bg">
              <Reveal className="h-full" delay={index * 110}>
                <div className="flex h-full flex-col gap-4 px-7 py-9 lg:px-9 lg:py-11">
                  <span className="font-display text-[13px] font-bold tracking-[0.18em] text-accent">
                    {step.ordinal}
                  </span>
                  <h3 className="font-display text-[clamp(1.35rem,2.4vw,1.75rem)]">
                    {step.title}
                  </h3>
                  <p className="text-[15px] leading-relaxed text-muted">{step.body}</p>
                </div>
              </Reveal>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
