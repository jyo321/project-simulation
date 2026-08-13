using Amazon.S3;
using Amazon.S3.Model;

namespace Northbridge.Shared.Storage;

public class S3ObjectStorageService : IObjectStorageService
{
    private readonly IAmazonS3 _s3;

    public S3ObjectStorageService(IAmazonS3 s3)
    {
        _s3 = s3;
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
        return _s3.GetPreSignedURL(request);
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
        return _s3.GetPreSignedURL(request);
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
