FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY Northbridge.Shared/Northbridge.Shared.csproj Northbridge.Shared/
COPY Applications.Api/Applications.Api.csproj Applications.Api/
RUN dotnet restore Applications.Api/Applications.Api.csproj
COPY Northbridge.Shared/ Northbridge.Shared/
COPY Applications.Api/ Applications.Api/
RUN dotnet publish Applications.Api/Applications.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Applications.Api.dll"]
