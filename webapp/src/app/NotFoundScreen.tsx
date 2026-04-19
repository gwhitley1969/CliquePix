import { Link } from 'react-router-dom';

export function NotFoundScreen() {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4 px-6 text-center">
      <h1 className="text-4xl font-bold bg-gradient-primary bg-clip-text text-transparent">
        404
      </h1>
      <p className="text-white/60">This page doesn't exist.</p>
      <Link to="/" className="text-aqua hover:underline">
        Back to Events
      </Link>
    </div>
  );
}
