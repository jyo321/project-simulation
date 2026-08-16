// Real AWS deployment — see the matching comment in applicant-portal's environment.prod.ts.
// This app is served under /reviewer/ (via --base-href) but its API calls stay at the
// site root, same CloudFront distribution, same ALB behind it.
export const environment = {
  production: true,
  decisioningApiBaseUrl: '/api',
  documentsApiBaseUrl: '/api',
};
