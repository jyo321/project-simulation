FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY backend/Northbridge.Shared/Northbridge.Shared.csproj backend/Northbridge.Shared/
COPY workers/DailyStaleReportJob/DailyStaleReportJob.csproj workers/DailyStaleReportJob/
RUN dotnet restore workers/DailyStaleReportJob/DailyStaleReportJob.csproj
COPY backend/Northbridge.Shared/ backend/Northbridge.Shared/
COPY workers/DailyStaleReportJob/ workers/DailyStaleReportJob/
RUN dotnet publish workers/DailyStaleReportJob/DailyStaleReportJob.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "DailyStaleReportJob.dll"]
