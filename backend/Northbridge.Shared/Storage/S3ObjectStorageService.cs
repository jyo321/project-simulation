using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Configuration;

namespace Northbridge.Shared.Storage;

public class S3ObjectStorageService : IObjectStorageService
{
    private readonly IAmazonS3 _s3;
    private readonly Uri? _publicServiceUri;

    /// <param name="configuration">
    /// Only used to read an optional "AWS:DefaultClientConfig:PublicServiceURL" — real AWS
    /// S3 endpoints are already publicly reachable, so this stays unset in production and
    /// presigned URLs are returned exactly as the SDK builds them. Local/demo deployments
    /// against LocalStack need it: the SDK signs presigned URLs against whatever ServiceURL
    /// the *server* uses to reach LocalStack (an internal Docker hostname like
    /// "localstack:4566"), which a browser outside that Docker network can never resolve.
    /// This rewrites just the scheme/host/port of the already-signed URL to a
    /// browser-reachable address, leaving the path and signature query string untouched.
    /// </param>
    public S3ObjectStorageService(IAmazonS3 s3, IConfiguration configuration)
    {
        _s3 = s3;
        var publicServiceUrl = configuration["AWS:DefaultClientConfig:PublicServiceURL"];
        _publicServiceUri = string.IsNullOrEmpty(publicServiceUrl) ? null : new Uri(publicServiceUrl);
    }

    public string GetPresignedUploadUrl(string bucket, string objectKey, string contentType, TimeSpan expiry)
    {
        var request = new GetPreSignedUrlRequest
        {
            BucketName = bucket,
            Key = objectKey,
            Verb = HttpVerb.PUT,
            Expires = DateTime.UtcNow.Add(expiry),
            ContentType = contentType,
        };
        return RewriteHostIfConfigured(_s3.GetPreSignedURL(request));
    }

    public string GetPresignedDownloadUrl(string bucket, string objectKey, TimeSpan expiry)
    {
        var request = new GetPreSignedUrlRequest
        {
            BucketName = bucket,
            Key = objectKey,
            Verb = HttpVerb.GET,
            Expires = DateTime.UtcNow.Add(expiry),
        };
        return RewriteHostIfConfigured(_s3.GetPreSignedURL(request));
    }

    private string RewriteHostIfConfigured(string presignedUrl)
    {
        if (_publicServiceUri is null) return presignedUrl;

        var rewritten = new UriBuilder(presignedUrl)
        {
            Scheme = _publicServiceUri.Scheme,
            Host = _publicServiceUri.Host,
            Port = _publicServiceUri.Port,
        };
        return rewritten.Uri.ToString();
    }

    public async Task PutObjectAsync(string bucket, string objectKey, Stream content, string contentType, CancellationToken ct = default)
    {
        await _s3.PutObjectAsync(new PutObjectRequest
        {
            BucketName = bucket,
            Key = objectKey,
            InputStream = content,
            ContentType = contentType,
        }, ct);
    }

    public async Task<Stream> GetObjectAsync(string bucket, string objectKey, CancellationToken ct = default)
    {
        var response = await _s3.GetObjectAsync(bucket, objectKey, ct);
        return response.ResponseStream;
    }
}
