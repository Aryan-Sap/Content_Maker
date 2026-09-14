"use client";

/* The preview illustrates the workflow; it never processes or uploads a file. */
/* eslint-disable @next/next/no-img-element */
import { useEffect, useRef, useState, type CSSProperties } from "react";
import { ArrowDown, ArrowLeft, ArrowRight, ArrowUpRight, Check, CheckCircle, CornersOut, DownloadSimple, FilmStrip, FolderSimple, InstagramLogo, Lightning, List, LockSimple, Monitor, MusicNote, Pause, Play, Plus, Scissors, SlidersHorizontal, Sparkle, TiktokLogo, UploadSimple, Waveform, WindowsLogo, X, YoutubeLogo } from "@phosphor-icons/react";
import "../creative-home.css";

const DOWNLOAD_URL = "https://contentmaker.site/downloads/ContentMakerSetup.exe";
const waveHeights = Array.from({ length: 54 }, (_, i) => 12 + ((i * 17 + i * i * 3) % 29));

function Brand() {
  return <a href="#top" className="brand" aria-label="Content Maker home"><svg width="34" height="34" viewBox="0 0 34 34" aria-hidden="true"><circle cx="17" cy="17" r="15" fill="none" stroke="currentColor" strokeWidth="2.4" /><path d="M10 23V11l7 8 7-8v12" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinejoin="round" /></svg><span>content<span className="brand-light">maker</span><i>.</i></span></a>;
}
function Wave({ className = "" }: { className?: string }) {
  return <div className={`wave ${className}`} aria-hidden="true">{waveHeights.map((height, i) => <i key={i} style={{ height, "--i": i } as CSSProperties} />)}</div>;
}
function EditorPlayground({ motionPaused }: { motionPaused: boolean }) {
  const [portrait, setPortrait] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [progress, setProgress] = useState(34);
  const [look, setLook] = useState("Original");
  useEffect(() => {
    if (!playing || motionPaused) return;
    const timer = window.setInterval(() => setProgress(p => p >= 100 ? 0 : p + 0.35), 100);
    return () => window.clearInterval(timer);
  }, [playing, motionPaused]);
  return <div className="playground-wrap"><div className="editor-window" id="playground">
    <div className="editor-topbar"><span className="window-dots"><i /><i /><i /></span><span>weekend-highlights.cm</span><span className="saved"><span /> Saved locally</span></div>
    <div className="editor-toolbar"><span><FilmStrip size={15} /> Preview your possibilities</span><div className="format-switch" aria-label="Preview aspect ratio"><button type="button" aria-pressed={!portrait} onClick={() => setPortrait(false)}>16:9</button><button type="button" aria-pressed={portrait} onClick={() => setPortrait(true)}>9:16</button></div></div>
    <div className={`editor-canvas ${portrait ? "is-portrait" : ""} look-${look.toLowerCase()}`}><img className="canvas-backdrop" src="/alpine-drift.webp" alt="" /><div className="canvas-image" style={{ "--pan": `${(progress - 50) / 22}%` } as CSSProperties}><img src="/alpine-drift.webp" alt="Illustrated racing footage: a red rally car drifting through an alpine valley" fetchPriority="high" width={1672} height={941} /><span className="canvas-frame-corner tl" /><span className="canvas-frame-corner tr" /><span className="canvas-frame-corner bl" /><span className="canvas-frame-corner br" /></div><span className="canvas-hint"><span /> {portrait ? "Made for the scroll" : "Keep the whole adventure"}</span><span className="canvas-quality">{portrait ? "1080 × 1920" : "1920 × 1080"}</span></div>
    <div className="playback-row"><button type="button" className="play-button" aria-label={playing ? "Pause preview" : "Play preview"} onClick={() => setPlaying(!playing)}>{playing ? <Pause weight="fill" /> : <Play weight="fill" />}</button><span>00:{String(Math.floor(progress * 0.24)).padStart(2, "0")} <em>/ 00:24</em></span><span className="preview-note">Interactive concept</span><CornersOut size={14} aria-hidden="true" /></div>
    <div className="timeline-preview"><div className="timeline-ruler"><span>00:00</span><span>00:06</span><span>00:12</span><span>00:18</span><span>00:24</span></div><div className="film-track" aria-hidden="true">{Array.from({ length: 7 }, (_, i) => <div key={i} style={{ backgroundPosition: `${i * 16}% 50%` }} />)}</div><Wave /><div className="playhead" style={{ left: `${4 + progress * 0.92}%` }} aria-hidden="true"><i /></div><input className="timeline-scrubber" type="range" min="0" max="100" value={progress} onChange={event => setProgress(Number(event.target.value))} aria-label="Scrub preview timeline" /></div>
    <div className="editor-bottom"><span><SlidersHorizontal size={13} /> The finishing touch</span><div>{["Original", "Warm", "Cinema"].map(style => <button type="button" key={style} aria-pressed={look === style} onClick={() => setLook(style)}>{style}</button>)}</div></div>
    </div><div className="floating-export" aria-hidden="true"><span className="export-icon"><Check size={21} weight="bold" /></span><div><b>Good to go.</b><span>Your next great Short.</span></div><ArrowUpRight size={21} /></div><div className="playground-note" aria-hidden="true"><svg viewBox="0 0 75 55"><path d="M3 5c33-10 45 14 45 34m-9-6 10 11 10-13" /></svg>Go on, try the controls.</div></div>;
}

const creatorSlides = [
  { title: "For the moment\nyou had to be there.", body: "The last-second clutch. The perfect drift. The unexpected win. Give your favorite moments a life beyond the recording folder.", tag: "The highlight maker", image: "/shot-raw-capture.png", alt: "A first-person competitive gaming highlight", icon: <Lightning weight="fill" /> },
  { title: "For the story\nbehind the session.", body: "Keep the whole adventure. Build a full-length video with multiple tracks, thoughtful cuts, and a look that feels like you.", tag: "The long-form storyteller", image: "/alpine-drift.webp", alt: "A cinematic alpine racing adventure", icon: <FilmStrip weight="fill" /> },
  { title: "For a little less\nediting. More playing.", body: "Drop in a recording and let Auto Render handle the vertical format. Get back to the part you love while your PC does the work.", tag: "The weekend creator", image: "/app-workspace-light.png", alt: "Content Maker's redesigned light project library", icon: <Monitor weight="fill" /> },
];
const questions = [
  ["Is it really free?", "Yes. Content Maker is free to download, edit with, and render with. Processing runs on your own PC, so there are no cloud rendering credits to buy."],
  ["What do I need to get started?", "A 64-bit Windows 10 or Windows 11 PC and a recording you want to edit. FFmpeg is bundled with the installer. No separate setup and no Content Maker account required."],
  ["Does my footage stay on my computer?", "Yes. Your source footage, projects, and renders stay on your device. A finished video is only uploaded when you choose to publish it to your connected account."],
  ["Can I make full-length videos too?", "Absolutely. Auto Render is designed for vertical Shorts. The Custom Timeline gives you multi-track editing, trims, splits, transitions, and color controls for landscape videos too."],
  ["How does publishing work?", "Connect YouTube or TikTok through their official sign-in flow, then upload from Content Maker. Availability and visibility depend on platform permissions. Instagram Reels uses a manual hand-off of your finished file."],
  ["Is there a Mac or mobile version?", "The current release is for Windows 10 and 11. An Android version is in development. A Mac release is not currently available."],
];

export default function CreativeHome() {
  const root = useRef<HTMLDivElement>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [motionPaused, setMotionPaused] = useState(false);
  const [slide, setSlide] = useState(0);
  const [activeFaq, setActiveFaq] = useState<number | null>(0);
  const [canvasFormat, setCanvasFormat] = useState("9:16");
  useEffect(() => {
    const keydown = (event: KeyboardEvent) => {
      if (event.key === "Escape") { setMenuOpen(false); root.current?.querySelector<HTMLButtonElement>(".mobile-menu-toggle")?.focus(); }
    };
    if (menuOpen) document.addEventListener("keydown", keydown);
    return () => document.removeEventListener("keydown", keydown);
  }, [menuOpen]);
  useEffect(() => {
    let cancelled = false;
    let cleanup: (() => void) | undefined;
    async function animate() {
    const [{ default: gsap }, { ScrollTrigger }] = await Promise.all([
      import("gsap"), import("gsap/ScrollTrigger"),
    ]);
    if (cancelled) return;
    gsap.registerPlugin(ScrollTrigger);
    const context = gsap.context(() => {
    const mm = gsap.matchMedia();
    mm.add("(prefers-reduced-motion: no-preference)", () => {
      if (motionPaused) return;
      gsap.from(".hero-enter", { y: 42, opacity: 0, duration: 1.05, stagger: 0.11, ease: "power3.out" });
      gsap.from(".playground-wrap", { y: 70, rotate: 4, opacity: 0, duration: 1.35, delay: 0.28, ease: "power3.out" });
      gsap.to(".floating-export", { y: -12, rotation: 1.5, repeat: -1, yoyo: true, duration: 3.4, ease: "sine.inOut" });
      gsap.to(".hero-orbit", { rotation: 14, scrollTrigger: { trigger: ".hero", start: "top top", end: "bottom top", scrub: 1.4 } });
      gsap.utils.toArray<HTMLElement>(".reveal-in").forEach(element => gsap.from(element, { y: 38, opacity: 0, duration: 0.9, ease: "power3.out", scrollTrigger: { trigger: element, start: "top 92%", once: true } }));
      gsap.fromTo(".manifesto-word", { opacity: 0.16 }, { opacity: 1, stagger: 0.16, ease: "none", scrollTrigger: { trigger: ".manifesto", start: "top 82%", end: "bottom 48%", scrub: 0.8 } });
      mm.add("(min-width: 960px)", () => {
        const cards = gsap.utils.toArray<HTMLElement>(".stack-card");
        cards.forEach((card, i) => {
          ScrollTrigger.create({ trigger: card, start: `top ${110 + i * 18}`, endTrigger: ".stack-end", end: "top 85%", pin: true, pinSpacing: false, invalidateOnRefresh: true });
          if (i < cards.length - 1) gsap.to(card, { scale: 0.94 + i * 0.015, ease: "none", transformOrigin: "top center", scrollTrigger: { trigger: cards[i + 1], start: "top bottom", end: `top ${128 + i * 18}`, scrub: true } });
        });
      });
    });
    return () => mm.revert();
    }, root);
    cleanup = () => context.revert();
    }
    void animate().catch(() => { /* Content stays usable if motion cannot load. */ });
    return () => { cancelled = true; cleanup?.(); };
  }, [motionPaused]);
  const creator = creatorSlides[slide];
  return <div ref={root} className={`cm-new-site${motionPaused ? " motion-paused" : ""}`}>
    <a href="#main-content" className="skip-link">Skip to content</a>
    <header className="site-header"><div className="nav-shell"><Brand /><nav className={`desktop-nav ${menuOpen ? "is-open" : ""}`} id="main-navigation" aria-label="Main navigation">{[["#how", "The workflow"], ["#features", "The toolkit"], ["#faq", "Good questions"]].map(([href, label]) => <a key={href} href={href} onClick={() => setMenuOpen(false)}>{label}</a>)}</nav><div className="nav-actions"><a className="nav-download" href="#download">Get it free <ArrowUpRight size={17} /></a><button type="button" className="mobile-menu-toggle" aria-expanded={menuOpen} aria-controls="main-navigation" aria-label={menuOpen ? "Close navigation" : "Open navigation"} onClick={() => setMenuOpen(!menuOpen)}>{menuOpen ? <X size={24} /> : <List size={24} />}</button></div></div></header>
    <main id="main-content" className="overflow-x-hidden w-full max-w-full">
      <section id="top" className="hero"><div className="hero-orbit" aria-hidden="true" /><div className="hero-heading hero-enter"><p className="eyebrow"><span /> LESS FUSS. MORE CREATING.</p><h1 className="max-w-6xl">Good clips.<br /><span>Great content.</span></h1></div><div className="hero-copy hero-enter"><p>You make the moments.<br />We make them ready to share.</p><p className="hero-description">Turn raw gameplay into polished Shorts and full-length videos. Edit, render, and publish from one free Windows app.</p><div className="hero-ctas"><a className="button button-coral" href="#download"><WindowsLogo size={19} weight="fill" /> Download free <ArrowUpRight size={18} /></a><a className="text-button" href="#how">See it in motion <span><ArrowDown size={17} /></span></a></div><p className="hero-footnote">Made for Windows. Made for your next idea.</p></div><EditorPlayground motionPaused={motionPaused} /><div className="hero-bottom"><span>A SMALL APP FOR BIG CREATIVE ENERGY.</span><a href="#how">Scroll to find your flow <ArrowDown size={15} /></a></div></section>
      <div className="marquee-band" aria-label="Edit. Render. Publish. Repeat."><div className="marquee-track" aria-hidden="true" style={{ animationPlayState: motionPaused ? "paused" : "running" }}>{Array.from({ length: 4 }, (_, i) => <div className="marquee-group" key={i}><span>MAKE THE CUT</span><Scissors /><span>FIND YOUR FLOW</span><Waveform /><span>HIT PUBLISH</span><ArrowUpRight /><span>GO AGAIN</span><Sparkle /></div>)}</div><button type="button" className="motion-toggle" aria-label={motionPaused ? "Resume animations" : "Pause animations"} aria-pressed={motionPaused} onClick={() => setMotionPaused(!motionPaused)}>{motionPaused ? <Play size={14} weight="fill" /> : <Pause size={14} weight="fill" />}</button></div>
      <section className="manifesto section-pad"><div className="section-shell"><p className="eyebrow reveal-in">YOUR IDEAS DESERVE TO GET OUT THERE.</p><h2>{["Less", "time", "in", "the", "timeline."].map((word, i) => <span className="manifesto-word" key={i}>{word} </span>)}<span className="inline-photo"><img src="/alpine-drift.webp" alt="" loading="lazy" /></span><br />{["More", "time", "making", "your", "next"].map((word, i) => <span className="manifesto-word" key={i}>{word} </span>)}<span className="manifesto-word serif-accent">great thing.</span></h2><p className="manifesto-caption reveal-in">The best part of creating should be creating.<br />Content Maker takes care of the in-between.</p></div></section>
      <section id="features" className="features-section section-pad"><div className="section-shell"><div className="section-heading reveal-in"><div><p className="eyebrow">SMALL APP. FULL CREATIVE TOOLKIT.</p><h2>All the good stuff.<br /><span className="muted-heading">None of the busywork.</span></h2></div><p>Go from a raw recording to something<br className="desktop-break" /> worth watching. Your way.</p></div><div className="feature-grid">
        <article className="feature-card auto-card reveal-in"><div className="card-copy"><span className="feature-icon"><Lightning size={23} /></span><h3>Shorts. In a shortcut.</h3><p>The right canvas, a blurred backdrop, and smooth 60 fps output. Auto Render does the heavy lifting.</p></div><div className="auto-visual" aria-hidden="true"><div className="source-thumbnail"><img src="/alpine-drift.webp" alt="" loading="lazy" /><span>your-very-good-clip.mp4</span></div><div className="conversion-path"><i /><Sparkle size={24} weight="fill" /><i /></div><div className="mini-short"><img className="short-blur" src="/alpine-drift.webp" alt="" loading="lazy" /><img className="short-foreground" src="/alpine-drift.webp" alt="" loading="lazy" /><span>That&apos;s the moment.</span></div></div><span className="card-caption">A LITTLE RAW. A LOT OF POTENTIAL.</span></article>
        <article className="feature-card timeline-card reveal-in"><div className="card-copy"><span className="feature-icon"><Scissors size={23} /></span><h3>Your edit. Your rules.</h3><p>Trim, split, layer, and color. A full timeline when the story calls for a little more you.</p></div><div className="layers-visual" aria-hidden="true"><div className="layer-ruler"><span>00:00</span><span>00:08</span><span>00:16</span></div><div className="layer purple-layer"><FilmStrip /> The good bit <span>clip 01</span></div><div className="layer peach-layer"><SlidersHorizontal /> A little warmth</div><div className="layer green-layer"><MusicNote /><Wave /></div><div className="layer-cursor" /></div></article>
        <article className="feature-card local-card reveal-in"><div className="card-copy"><span className="feature-icon"><LockSimple size={23} /></span><h3>Yours. All the way.</h3><p>Your footage stays on your PC. Local rendering. No cloud queue. Just you and your creative space.</p></div><div className="local-visual" aria-hidden="true"><div className="local-orbit orbit-one" /><div className="local-orbit orbit-two" /><div className="local-file"><FolderSimple size={32} weight="duotone" /><span>the next big thing</span><b><CheckCircle size={13} weight="fill" /> On your device</b></div><span className="local-lock"><LockSimple size={21} weight="fill" /></span></div></article>
        <article className="feature-card format-card reveal-in"><div className="card-copy"><span className="feature-icon"><CornersOut size={23} /></span><h3>Different canvas. Same you.</h3><p>A quick Short or the full story. Make space for every kind of idea.</p></div><div className="format-demo"><div className={`format-preview ${canvasFormat === "16:9" ? "landscape" : "portrait"}`}><img src="/alpine-drift.webp" alt={`${canvasFormat} format preview of racing footage`} loading="lazy" /><span>{canvasFormat}</span></div><div className="format-options">{["9:16", "16:9"].map(format => <button type="button" key={format} aria-pressed={canvasFormat === format} onClick={() => setCanvasFormat(format)}><span className={format === "9:16" ? "portrait-glyph" : "landscape-glyph"} />{format === "9:16" ? "The Short" : "The full story"}</button>)}</div></div></article>
      </div></div></section>
      <section id="how" className="workflow-section section-pad"><div className="section-shell"><div className="section-heading reveal-in"><div><p className="eyebrow">FROM THE FOLDER TO THE FEED.</p><h2>Find your flow.<br /><span className="serif-accent">Keep your momentum.</span></h2></div><span className="workflow-scroll-note">THREE MOVES. ONE APP.<ArrowDown size={24} /></span></div><div className="workflow-stack">
        <article className="stack-card stack-import"><div className="stack-copy"><span className="step-symbol"><FolderSimple size={27} /></span><h3>Start with<br />a good moment.</h3><p>Drop in a whole session or a single clip. Pick the part that deserves another watch.</p><span className="stack-bottom">YOUR RAW FOOTAGE <ArrowRight size={20} /></span></div><div className="import-scene"><div className="file-card file-back"><FilmStrip size={26} /><span>weekend-session.mp4</span></div><div className="file-card file-front"><img src="/alpine-drift.webp" alt="Sample clip ready to edit" loading="lazy" /><div><FilmStrip size={19} /><span>the-perfect-drift.mp4<small>A moment worth keeping.</small></span><CheckCircle size={22} weight="fill" /></div></div><div className="drop-zone"><UploadSimple size={23} /><span>A little potential. Dropped right in.</span></div></div></article>
        <article className="stack-card stack-edit"><div className="stack-copy"><span className="step-symbol"><SlidersHorizontal size={27} /></span><h3>Make it<br />feel like you.</h3><p>Take the shortcut with Auto Render, or shape every frame in the Custom Timeline. Your creative call.</p><span className="stack-bottom">YOUR SIGNATURE STYLE <ArrowRight size={20} /></span></div><div className="edit-scene"><div className="edit-shot"><img src="/alpine-drift.webp" alt="A racing frame with warm cinematic color styling" loading="lazy" /><span><Sparkle size={15} /> A little cinematic magic.</span></div><div className="style-controls"><span>Warmth<i><b /></i></span><span>Contrast<i><b /></i></span><span>That feeling<i><b /></i></span></div></div></article>
        <article className="stack-card stack-publish"><div className="stack-copy"><span className="step-symbol"><ArrowUpRight size={27} /></span><h3>Out of the editor.<br />Into the world.</h3><p>Render on your PC, then publish to YouTube or TikTok. Your next post, all from the same creative space.</p><span className="stack-bottom">YOUR MOMENT, SHARED <ArrowUpRight size={20} /></span></div><div className="publish-scene"><div className="publish-file"><CheckCircle size={40} weight="fill" /><h4>Ready for its close-up.</h4><p>Your finished video. Your next move.</p><div className="platform-line"><span><YoutubeLogo weight="fill" size={23} /> YouTube</span><ArrowUpRight size={17} /></div><div className="platform-line"><span><TiktokLogo weight="fill" size={21} /> TikTok</span><ArrowUpRight size={17} /></div><div className="platform-footnote"><InstagramLogo size={15} /> Reels? Export and upload your way.</div></div></div></article><div className="stack-end" />
      </div></div></section>
      <section className="creator-section section-pad"><div className="section-shell creator-grid"><div className={`creator-image reveal-in${slide === 2 ? " creator-image-app" : ""}`} key={`image-${slide}`}><img src={creator.image} alt={creator.alt} loading="lazy" /><span className="creator-image-caption">BIG CREATIVE ENERGY. YOUR KIND OF CONTENT.</span><span className="creator-image-icon">{creator.icon}</span></div><div className="creator-copy reveal-in"><p className="eyebrow">THERE&apos;S A CREATOR IN THERE.</p><div className="creator-slide" key={slide} aria-live="polite" aria-atomic="true"><h2>{creator.title.split("\n").map((line, i) => <span key={i}>{line}{i === 0 && <br />}</span>)}</h2><p>{creator.body}</p><span className="creator-type">{creator.icon}{creator.tag}</span></div><div className="carousel-controls"><div className="carousel-dots" aria-label="Choose a creator workflow">{creatorSlides.map((item, i) => <button type="button" key={item.tag} className={i === slide ? "active" : ""} aria-label={`Show ${item.tag.toLowerCase()}`} aria-pressed={i === slide} onClick={() => setSlide(i)} />)}</div><div><button type="button" className="circle-button" aria-label="Previous creator workflow" onClick={() => setSlide((slide + 2) % 3)}><ArrowLeft size={20} /></button><button type="button" className="circle-button" aria-label="Next creator workflow" onClick={() => setSlide((slide + 1) % 3)}><ArrowRight size={20} /></button></div></div></div></div></section>
      <section id="faq" className="faq-section section-pad"><div className="section-shell faq-grid"><div className="reveal-in"><p className="eyebrow">A FEW THINGS YOU MIGHT BE WONDERING.</p><h2>Good questions.<br /><span className="serif-accent">Straight answers.</span></h2><p className="faq-aside">Less mystery. More making.</p></div><div className="faq-list reveal-in">{questions.map(([question, answer], i) => <div className={`faq-item ${activeFaq === i ? "open" : ""}`} key={question}><h3><button type="button" aria-expanded={activeFaq === i} aria-controls={`faq-answer-${i}`} id={`faq-question-${i}`} onClick={() => setActiveFaq(activeFaq === i ? null : i)}>{question}<Plus size={19} /></button></h3><div className="faq-answer" id={`faq-answer-${i}`} role="region" aria-labelledby={`faq-question-${i}`} hidden={activeFaq !== i}><p>{answer}</p></div></div>)}</div></div></section>
      <section id="download" className="download-section"><div className="download-orbit" aria-hidden="true" /><div className="section-shell download-content"><p className="eyebrow reveal-in">FREE TO MAKE SOMETHING GREAT.</p><h2 className="reveal-in">You&apos;ve got the footage.<br /><span>Let&apos;s make something.</span></h2><p className="reveal-in">Your next great video is already on your hard drive.</p><a className="button button-dark reveal-in" href={DOWNLOAD_URL}><WindowsLogo size={22} weight="fill" /> Download for Windows <DownloadSimple size={21} /></a><span className="download-details">Free · Windows 10 & 11 · 64-bit · FFmpeg included</span><span className="android-note">Android is in the making.</span></div><div className="download-doodle" aria-hidden="true"><svg viewBox="0 0 130 120"><path d="M20 14c17 19 58 4 63 30 5 29-47 40-19 62m-19-6 21 11 9-22" /></svg></div></section>
    </main>
    <footer className="site-footer"><div className="section-shell"><div className="footer-top"><Brand /><p>Make content.<br />Make it yours.</p><nav aria-label="Footer navigation"><a href="#features">The toolkit</a><a href="#how">The workflow</a><a href="#faq">FAQ</a><a href="/privacy">Privacy policy</a></nav><a href="#top" className="back-top" aria-label="Back to top"><ArrowUpRight size={25} /></a></div><div className="footer-bottom"><span>© 2026 Content Maker</span><span>BUILT FOR THE LOVE OF MAKING.</span><button type="button" onClick={() => setMotionPaused(!motionPaused)}>{motionPaused ? <Play size={13} /> : <Pause size={13} />}{motionPaused ? "Resume motion" : "Pause motion"}</button></div><div className="footer-word" aria-hidden="true">go make<span>.</span></div></div></footer>
  </div>;
}
