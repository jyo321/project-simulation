FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY backend/Northbridge.Shared/Northbridge.Shared.csproj backend/Northbridge.Shared/
COPY workers/CreditScoringJob/CreditScoringJob.csproj workers/CreditScoringJob/
RUN dotnet restore workers/CreditScoringJob/CreditScoringJob.csproj
COPY backend/Northbridge.Shared/ backend/Northbridge.Shared/
COPY workers/CreditScoringJob/ workers/CreditScoringJob/
RUN dotnet publish workers/CreditScoringJob/CreditScoringJob.csproj -c Release -o /app --no-restore

# Fire-and-forget task: sized for heavy, long-running compute (see infra/terraform/ecs.tf,
# 4 vCPU / 8-16GB task definition) — no ALB/API request-lifetime timeout applies here.
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "CreditScoringJob.dll"]
