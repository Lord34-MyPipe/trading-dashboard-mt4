import './globals.css';

export const metadata = {
  title: 'Trading Dashboard — JB',
  description: 'Dashboard trading multi-comptes MT4',
  manifest: '/manifest.json',
  themeColor: '#0a0e1a',
  viewport: {
    width: 'device-width',
    initialScale: 1,
    maximumScale: 1,
    userScalable: false,
    viewportFit: 'cover',
  },
  appleWebApp: {
    capable: true,
    statusBarStyle: 'black-translucent',
    title: 'Trading JB',
  },
};

export default function RootLayout({ children }) {
  return (
    <html lang="fr">
      <head>
        <link rel="apple-touch-icon" href="/icon-192.png" />
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
      </head>
      <body className="safe-top safe-bottom">{children}</body>
    </html>
  );
}
