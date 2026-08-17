# Built as a Lambda container image (not a standing ECS task) — see infra/terraform/lambda.tf.
# The public.ecr.aws/lambda/dotnet base image supplies the Lambda Runtime Interface Client;
# CMD below is the handler in "Assembly::Namespace.Type::Method" form.
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY backend/Northbridge.Shared/Northbridge.Shared.csproj backend/Northbridge.Shared/
COPY workers/DailyStaleReportJob/DailyStaleReportJob.csproj workers/DailyStaleReportJob/
RUN dotnet restore workers/DailyStaleReportJob/DailyStaleReportJob.csproj
COPY backend/Northbridge.Shared/ backend/Northbridge.Shared/
COPY workers/DailyStaleReportJob/ workers/DailyStaleReportJob/
RUN dotnet publish workers/DailyStaleReportJob/DailyStaleReportJob.csproj -c Release -o /app --no-restore

FROM public.ecr.aws/lambda/dotnet:8 AS runtime
WORKDIR ${LAMBDA_TASK_ROOT}
COPY --from=build /app .
CMD ["DailyStaleReportJob::DailyStaleReportJob.Function::FunctionHandler"]
