FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY Northbridge.Shared/Northbridge.Shared.csproj Northbridge.Shared/
COPY Documents.Api/Documents.Api.csproj Documents.Api/
RUN dotnet restore Documents.Api/Documents.Api.csproj
COPY Northbridge.Shared/ Northbridge.Shared/
COPY Documents.Api/ Documents.Api/
RUN dotnet publish Documents.Api/Documents.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Documents.Api.dll"]
