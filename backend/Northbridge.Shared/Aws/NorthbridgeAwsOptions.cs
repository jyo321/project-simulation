using Amazon.Extensions.NETCore.Setup;
using Amazon.S3;
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

    /// <summary>
    /// S3 needs its own config type because <c>ForcePathStyle</c> only exists on
    /// <see cref="AmazonS3Config"/>, not the generic <c>ClientConfig</c> that
    /// <see cref="AWSOptions.DefaultClientConfig"/> uses. Without it, the SDK addresses
    /// buckets virtual-hosted-style (<c>https://&lt;bucket&gt;.&lt;host&gt;/...</c>), which
    /// LocalStack doesn't resolve — every PutObject/GetObject call fails with a DNS error
    /// like "Name or service not known (generated-documents.localstack)". Path-style
    /// (<c>https://&lt;host&gt;/&lt;bucket&gt;/...</c>) is what LocalStack expects.
    /// </summary>
    public static AmazonS3Config BuildS3Config(IConfiguration configuration)
    {
        var options = Build(configuration);
        var config = new AmazonS3Config { RegionEndpoint = options.Region };

        if (!string.IsNullOrEmpty(options.DefaultClientConfig.ServiceURL))
        {
            config.ServiceURL = options.DefaultClientConfig.ServiceURL;
            config.UseHttp = options.DefaultClientConfig.UseHttp;
            config.AuthenticationRegion = options.DefaultClientConfig.AuthenticationRegion;
            config.ForcePathStyle = true;
        }

        return config;
    }
}
