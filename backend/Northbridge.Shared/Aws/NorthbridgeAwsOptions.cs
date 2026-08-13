using Amazon.Extensions.NETCore.Setup;
using Microsoft.Extensions.Configuration;

namespace Northbridge.Shared.Aws;

/// <summary>
/// Builds <see cref="AWSOptions"/> for every API/worker. `IConfiguration.GetAWSOptions()`
/// (from AWSSDK.Extensions.NETCore.Setup) only ever reads Profile/Region from config — it
/// silently ignores a "DefaultClientConfig" section, so an env var like
/// `AWS__DefaultClientConfig__ServiceURL` (used to point the AWS SDK at LocalStack for local
/// dev — see docker-compose.yml) has no effect unless applied here in code. Every client
/// still talks to real AWS in production, where ServiceURL/UseHttp are simply left unset.
/// </summary>
public static class NorthbridgeAwsOptions
{
    public static AWSOptions Build(IConfiguration configuration)
    {
        var options = configuration.GetAWSOptions();

        var serviceUrl = configuration["AWS:DefaultClientConfig:ServiceURL"];
        if (!string.IsNullOrEmpty(serviceUrl))
        {
            options.DefaultClientConfig.ServiceURL = serviceUrl;
            options.DefaultClientConfig.UseHttp = bool.TryParse(configuration["AWS:DefaultClientConfig:UseHttp"], out var useHttp) && useHttp;
            // LocalStack doesn't do real region-based endpoint resolution — pinning the
            // signing region avoids SigV4 mismatches once ServiceURL is overridden.
            options.DefaultClientConfig.AuthenticationRegion = options.Region?.SystemName ?? "us-east-1";
        }

        return options;
    }
}
