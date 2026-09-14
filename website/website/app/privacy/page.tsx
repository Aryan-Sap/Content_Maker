import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy | Content Maker",
  description: "How Content Maker handles videos, social account connections, and Google user data.",
};

const updated = "17 August 2026";

export default function PrivacyPage() {
  return (
    <main className="privacy-page">
      <article className="privacy-card">
        <Link className="privacy-back" href="/">
          ← Content Maker
        </Link>
        <p className="privacy-eyebrow">LEGAL</p>
        <h1>Privacy Policy</h1>
        <p className="privacy-updated">Last updated: {updated}</p>

        <p>
          Content Maker is a Windows desktop application that lets you edit
          videos on your computer and, when you choose, publish them to your
          own social-media accounts. This policy explains how the application
          handles your information.
        </p>

        <h2>Information processed locally</h2>
        <p>
          Your source videos, rendered videos, edit settings, titles, captions,
          tags, and publishing preferences are processed and kept on your own
          device. Content Maker does not upload these files to a Content Maker
          server.
        </p>

        <h2>Google and YouTube data</h2>
        <p>
          When you choose to connect YouTube, Google handles the sign-in and
          consent process. Content Maker never receives or stores your Google
          password. With your permission, the app uses Google OAuth tokens to
          identify the connected YouTube channel and upload the video and the
          metadata you selected, such as its title and privacy setting.
        </p>
        <p>
          The authorization tokens and connected-channel details are stored in
          your operating system’s secure credential store, not on a Content
          Maker server. Google user data is used only to provide the YouTube
          connection and upload feature that you request. It is not sold, used
          for advertising, or shared with third parties except YouTube as
          necessary to complete the upload you initiated.
        </p>
        <p>
          Google’s privacy policy is available at{" "}
          <a href="https://policies.google.com/privacy">policies.google.com/privacy</a>.
        </p>

        <h2>Other connected platforms</h2>
        <p>
          If you choose to connect another supported platform, such as TikTok
          or Instagram, the app uses that platform’s authorization process and
          sends only the video and publishing information needed for the action
          you explicitly start. The platform’s own privacy policy also applies.
        </p>

        <h2>Your choices and deletion</h2>
        <p>
          You can disconnect a connected account from Content Maker at any
          time. This removes its locally stored authorization data from the
          app. You can also revoke Content Maker’s access to your Google
          account from Google’s{" "}
          <a href="https://myaccount.google.com/permissions">third-party access settings</a>.
          Deleting a local video or uninstalling the app does not delete videos
          already published to a social-media platform; manage those directly
          with that platform.
        </p>

        <h2>Security</h2>
        <p>
          Content Maker uses the operating system’s secure credential storage
          for account tokens. No method of electronic storage or transmission
          is completely secure, so please keep your computer and operating
          system account protected.
        </p>

        <h2>Changes to this policy</h2>
        <p>
          We may update this policy when the app or its connected services
          change. The current version will always be posted on this page.
        </p>

        <h2>Contact</h2>
        <p>
          For privacy questions, contact{" "}
          <a href="mailto:aryan.saproo@gmail.com">aryan.saproo@gmail.com</a>.
        </p>
      </article>
    </main>
  );
}
