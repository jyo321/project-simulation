FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY backend/Northbridge.Shared/Northbridge.Shared.csproj backend/Northbridge.Shared/
COPY workers/StatusProjectorWorker/StatusProjectorWorker.csproj workers/StatusProjectorWorker/
RUN dotnet restore workers/StatusProjectorWorker/StatusProjectorWorker.csproj
COPY backend/Northbridge.Shared/ backend/Northbridge.Shared/
COPY workers/StatusProjectorWorker/ workers/StatusProjectorWorker/
RUN dotnet publish workers/StatusProjectorWorker/StatusProjectorWorker.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "StatusProjectorWorker.dll"]
