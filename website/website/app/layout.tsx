import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("host") ?? "localhost:3000";
  const protocol = host.startsWith("localhost") ? "http" : "https";
  const baseUrl = new URL(`${protocol}://${host}`);

  return {
    metadataBase: baseUrl,
    icons: {
      icon: [
        {
          url: "/content-maker-icon.png",
          type: "image/png",
          sizes: "512x512",
        },
      ],
      shortcut: "/content-maker-icon.png",
      apple: "/content-maker-icon.png",
    },
    title: "Content Maker — Make Content Easy",
    description:
      "Turn raw gameplay into polished 60 fps Shorts, edit full-length videos, and publish from one free Windows app.",
    openGraph: {
      title: "Content Maker — Make Content Easy",
      description: "Raw gameplay in. Ready-to-post Shorts out. Free for Windows.",
      type: "website",
      images: [
        {
          url: "/og.png",
          width: 1728,
          height: 904,
          alt: "Content Maker turns raw gameplay into ready-to-post Shorts",
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title: "Content Maker — Make Content Easy",
      description: "Raw gameplay in. Ready-to-post Shorts out. Free for Windows.",
      images: ["/og.png"],
    },
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
