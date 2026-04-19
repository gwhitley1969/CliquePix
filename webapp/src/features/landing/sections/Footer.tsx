export function Footer() {
  const year = new Date().getFullYear();
  return (
    <footer className="bg-dark-bg border-t border-white/5">
      <div className="max-w-6xl mx-auto px-4 md:px-8 py-10 flex flex-col md:flex-row items-start md:items-center justify-between gap-6">
        <div className="flex items-center gap-3">
          <img src="/assets/icon.png" alt="" className="w-8 h-8 rounded-lg" />
          <div>
            <div className="text-sm font-semibold text-white">Clique Pix</div>
            <div className="text-xs text-white/50">Private event photo and video sharing</div>
          </div>
        </div>

        <nav className="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-white/60">
          <a href="/docs/privacy" className="hover:text-white transition-colors">
            Privacy
          </a>
          <a href="/docs/terms" className="hover:text-white transition-colors">
            Terms
          </a>
          <a href="mailto:hello@clique-pix.com" className="hover:text-white transition-colors">
            Contact
          </a>
        </nav>

        <div className="text-xs text-white/40">© {year} Clique Pix</div>
      </div>
    </footer>
  );
}
