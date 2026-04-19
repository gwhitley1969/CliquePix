import { useEffect } from 'react';
import { LandingNav } from './sections/LandingNav';
import { Hero } from './sections/Hero';
import { HowItWorks } from './sections/HowItWorks';
import { Features } from './sections/Features';
import { UseCases } from './sections/UseCases';
import { BuiltDifferently } from './sections/BuiltDifferently';
import { Download } from './sections/Download';
import { Footer } from './sections/Footer';

export function LandingPage() {
  useEffect(() => {
    document.title = 'Clique Pix — Private photo sharing for real-life moments';
  }, []);

  return (
    <div className="min-h-screen bg-dark-bg text-white">
      <LandingNav />
      <main>
        <Hero />
        <HowItWorks />
        <Features />
        <UseCases />
        <BuiltDifferently />
        <Download />
      </main>
      <Footer />
    </div>
  );
}
