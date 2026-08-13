namespace Documents.Api.Dtos;

public record CreateUploadUrlRequest(Guid LoanApplicationId, string Type, string FileName, string ContentType);

public record CreateUploadUrlResponse(Guid DocumentId, string UploadUrl, string Bucket, string ObjectKey);

public record DocumentResponse(
    Guid Id,
    Guid LoanApplicationId,
    string Type,
    string Status,
    string FileName,
    DateTimeOffset UploadedAt,
    DateTimeOffset? ValidatedAt);

public record DownloadUrlResponse(string DownloadUrl);
