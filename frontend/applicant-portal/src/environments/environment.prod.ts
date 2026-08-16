// Real AWS deployment (infra/terraform): the ALB routes all three APIs behind ONE
// domain purely by path pattern (see infra/terraform/ecs.tf's listener rules — e.g.
// "/api/applicants*" and "/api/applications*" both go to Applications.Api) with no
// prefix stripping, unlike the EC2/nginx path (environment.ec2.ts). So every base URL
// here is the same domain + "/api" — replace API_DOMAIN with the real domain you
// pointed at the ALB's DNS name (terraform output alb_dns_name) before building.
const API_DOMAIN = 'api.northbridgelending.com'; // <-- replace with your real domain

export const environment = {
  production: true,
  applicationsApiBaseUrl: `https://${API_DOMAIN}/api`,
  documentsApiBaseUrl: `https://${API_DOMAIN}/api`,
};
