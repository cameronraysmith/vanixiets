import { DevTools } from '@/components/dev-tools';
import { Toaster } from '@/components/ui/toaster';

import type { Metadata } from 'next';

import './globals.css';

export const metadata: Metadata = {
  title: 'Beads',
  description: 'Kanban interface for beads - git-backed distributed issue tracker',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body className="flex min-h-screen flex-col bg-background antialiased font-sans">
        <div className="flex-1">{children}</div>
        <Toaster />
        <DevTools />
      </body>
    </html>
  );
}
