// Relative paths — nginx (see deploy/ec2/nginx.conf) reverse-proxies these same-origin,
// so the browser never needs a hardcoded host/IP and there's no cross-origin request at
// all. In the full AWS deployment (infra/terraform), CloudFront/ALB play the same role.
export const environment = {
  production: true,
  applicationsApiBaseUrl: '/applications-api/api',
  documentsApiBaseUrl: '/documents-api/api',
};
