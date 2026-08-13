FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY backend/Northbridge.Shared/Northbridge.Shared.csproj backend/Northbridge.Shared/
COPY workers/DocumentValidationWorker/DocumentValidationWorker.csproj workers/DocumentValidationWorker/
RUN dotnet restore workers/DocumentValidationWorker/DocumentValidationWorker.csproj
COPY backend/Northbridge.Shared/ backend/Northbridge.Shared/
COPY workers/DocumentValidationWorker/ workers/DocumentValidationWorker/
RUN dotnet publish workers/DocumentValidationWorker/DocumentValidationWorker.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "DocumentValidationWorker.dll"]
