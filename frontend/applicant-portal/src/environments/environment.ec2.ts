// EC2/nginx deployment only (see deploy/ec2/). Relative paths — nginx (deploy/ec2/nginx.conf)
// reverse-proxies these same-origin and strips the prefix itself, so the browser never needs
// a hardcoded host/IP. The real AWS deployment (CloudFront/ALB, infra/terraform) uses
// environment.prod.ts instead, since the ALB does path-based routing with no prefix
// stripping — build with `--configuration ec2` specifically to get this file instead.
export const environment = {
  production: true,
  applicationsApiBaseUrl: '/applications-api/api',
  documentsApiBaseUrl: '/documents-api/api',
};
