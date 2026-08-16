// Real AWS deployment — see the matching comment in applicant-portal's environment.prod.ts.
// Same ALB, same domain, no prefix stripping.
const API_DOMAIN = 'api.northbridgelending.com'; // <-- replace with your real domain

export const environment = {
  production: true,
  decisioningApiBaseUrl: `https://${API_DOMAIN}/api`,
  documentsApiBaseUrl: `https://${API_DOMAIN}/api`,
};
