import Wordmark from "./Wordmark";

const links = [
  { href: "#how", label: "How it works" },
  { href: "#features", label: "Features" },
  { href: "#pricing", label: "Pricing" },
  { href: "#faq", label: "FAQ" },
];

export default function Nav() {
  return (
    <header className="sticky top-0 z-40 border-b border-line/70 bg-bg/85 backdrop-blur-xl">
      <nav className="mx-auto flex h-[68px] max-w-[1240px] items-center justify-between gap-6 px-5 sm:px-8">
        <a href="#top" className="text-ink no-underline" aria-label="Content Maker home">
          <Wordmark />
        </a>

        <div className="hidden items-center gap-8 lg:flex">
          {links.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="text-[14px] font-medium text-muted no-underline transition-colors duration-200 hover:text-ink"
            >
              {link.label}
            </a>
          ))}
        </div>

        <a
          href="#download"
          className="rounded-control bg-accent px-4 py-2.5 text-[13px] font-semibold whitespace-nowrap text-on-accent no-underline transition-transform duration-200 hover:-translate-y-px active:translate-y-0 sm:px-5 sm:text-[14px]"
        >
          Download for Windows
        </a>
      </nav>
    </header>
  );
}
