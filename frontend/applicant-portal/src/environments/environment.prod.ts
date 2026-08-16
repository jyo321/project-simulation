// Real AWS deployment (infra/terraform): CloudFront fronts both the S3 static assets AND
// the ALB (see infra/terraform/cloudfront_frontend.tf's ordered_cache_behavior for
// "/api/*"), so the SPA's own CloudFront domain doubles as the API's public address — no
// separate domain, no ACM certificate, no Route 53. The ALB's own path-based routing
// (ecs.tf's listener rules — "/api/applicants*", "/api/applications*", etc.) does the
// rest, so a plain relative "/api" is all that's needed here.
export const environment = {
  production: true,
  applicationsApiBaseUrl: '/api',
  documentsApiBaseUrl: '/api',
};
