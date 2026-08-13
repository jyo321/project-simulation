FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY backend/Northbridge.Shared/Northbridge.Shared.csproj backend/Northbridge.Shared/
COPY notification-service/NotificationWorker/NotificationWorker.csproj notification-service/NotificationWorker/
RUN dotnet restore notification-service/NotificationWorker/NotificationWorker.csproj
COPY backend/Northbridge.Shared/ backend/Northbridge.Shared/
COPY notification-service/NotificationWorker/ notification-service/NotificationWorker/
RUN dotnet publish notification-service/NotificationWorker/NotificationWorker.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "NotificationWorker.dll"]
