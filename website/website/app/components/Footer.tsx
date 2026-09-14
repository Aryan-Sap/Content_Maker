import Wordmark from "./Wordmark";

const links = [
  { href: "#how", label: "How it works" },
  { href: "#features", label: "Features" },
  { href: "#faq", label: "FAQ" },
  { href: "/privacy", label: "Privacy" },
];

export default function Footer() {
  return (
    <footer className="border-t border-line/60 py-12">
      <div className="mx-auto flex max-w-[1240px] flex-col items-start justify-between gap-8 px-5 sm:px-8 md:flex-row md:items-center">
        <div>
          <Wordmark size={26} />
          <p className="mt-3 text-[13px] text-faint">
            Make Content Easy. Copyright 2026 Content Maker.
          </p>
        </div>

        <nav className="flex flex-wrap gap-x-7 gap-y-3">
          {links.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="text-[13.5px] text-muted no-underline transition-colors duration-200 hover:text-accent"
            >
              {link.label}
            </a>
          ))}
        </nav>
      </div>
    </footer>
  );
}
