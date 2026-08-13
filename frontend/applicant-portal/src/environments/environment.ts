// CSR SPA is deployed to its own S3 bucket + CloudFront distribution (see docs/architecture.md
// §4). It talks to the three .NET APIs over REST through the shared ALB — no server-side
// rendering, no backend-for-frontend, matching the brief's "micro frontend, independently
// deployed" requirement.
export const environment = {
  production: false,
  applicationsApiBaseUrl: 'http://localhost:5001/api',
  documentsApiBaseUrl: 'http://localhost:5002/api',
};
