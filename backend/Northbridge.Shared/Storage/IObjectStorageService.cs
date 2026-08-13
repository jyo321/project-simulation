namespace Northbridge.Shared.Storage;

public interface IObjectStorageService
{
    /// <summary>Pre-signed PUT URL so the applicant's browser uploads straight to S3.</summary>
    string GetPresignedUploadUrl(string bucket, string objectKey, string contentType, TimeSpan expiry);

    /// <summary>Pre-signed GET URL so the Reviewer Console can view/download a document.</summary>
    string GetPresignedDownloadUrl(string bucket, string objectKey, TimeSpan expiry);

    Task PutObjectAsync(string bucket, string objectKey, Stream content, string contentType, CancellationToken ct = default);

    Task<Stream> GetObjectAsync(string bucket, string objectKey, CancellationToken ct = default);
}
