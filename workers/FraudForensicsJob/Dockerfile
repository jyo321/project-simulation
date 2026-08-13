FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY backend/Northbridge.Shared/Northbridge.Shared.csproj backend/Northbridge.Shared/
COPY workers/FraudForensicsJob/FraudForensicsJob.csproj workers/FraudForensicsJob/
RUN dotnet restore workers/FraudForensicsJob/FraudForensicsJob.csproj
COPY backend/Northbridge.Shared/ backend/Northbridge.Shared/
COPY workers/FraudForensicsJob/ workers/FraudForensicsJob/
RUN dotnet publish workers/FraudForensicsJob/FraudForensicsJob.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "FraudForensicsJob.dll"]
