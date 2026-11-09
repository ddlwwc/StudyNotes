import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "StudyNotes",
  description: "本地优先、资料有据的个人 AI 私教"
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
