// CSR SPA is deployed to its own S3 bucket + CloudFront distribution (see docs/architecture.md
// §4). It talks to the three .NET APIs over REST through the shared ALB — no server-side
// rendering, no backend-for-frontend, matching the brief's "micro frontend, independently
// deployed" requirement.
//
// Dev config only (production build uses environment.prod.ts's relative paths instead):
// derives the API host from wherever this page was loaded from, rather than hardcoding
// "localhost" — so the exact same build works whether you open it at localhost:4200 (local
// dev) or http://<vm-ip>:4200 (running on an EC2/VM instead of your own machine) without
// any code change, as long as the APIs' ports are reachable at that same host.
const apiHost = typeof window !== 'undefined' ? window.location.hostname : 'localhost';

export const environment = {
  production: false,
  applicationsApiBaseUrl: `http://${apiHost}:5001/api`,
  documentsApiBaseUrl: `http://${apiHost}:5002/api`,
};
