// EC2/nginx deployment only (see deploy/ec2/) — build with `--configuration ec2`.
// This app is served under /reviewer/ (see nginx.conf and the --base-href flag in
// deploy/ec2/README.md); its API calls stay at the site root, same as applicant-portal.
export const environment = {
  production: true,
  decisioningApiBaseUrl: '/decisioning-api/api',
  documentsApiBaseUrl: '/documents-api/api',
};
