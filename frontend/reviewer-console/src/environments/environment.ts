// Dev config only — derives the API host from wherever this page was loaded from (see the
// matching comment in applicant-portal's environment.ts) so it works unchanged whether
// you're at localhost:4201 or http://<vm-ip>:4201.
const apiHost = typeof window !== 'undefined' ? window.location.hostname : 'localhost';

export const environment = {
  production: false,
  decisioningApiBaseUrl: `http://${apiHost}:5003/api`,
  documentsApiBaseUrl: `http://${apiHost}:5002/api`,
};
