// Relative paths — nginx (see deploy/ec2/nginx.conf) reverse-proxies these same-origin.
// This app is served under the /reviewer/ path (see nginx.conf and the --base-href flag
// in deploy/ec2/README.md), but its API calls stay at the site root, same as applicant-portal.
export const environment = {
  production: true,
  decisioningApiBaseUrl: '/decisioning-api/api',
  documentsApiBaseUrl: '/documents-api/api',
};
