import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "StudyNotes · 公开学习资料",
    template: "%s · StudyNotes"
  },
  description: "浏览已发布的学习文章，支持全站搜索、目录、公开研读层与独立导出。",
  robots: {
    index: false,
    follow: false,
    nocache: true
  }
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#FFFFFF"
};

export default function RootLayout({
  children
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
