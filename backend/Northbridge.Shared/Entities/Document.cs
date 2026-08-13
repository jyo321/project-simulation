using Northbridge.Shared.Enums;

namespace Northbridge.Shared.Entities;

public class Document
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid LoanApplicationId { get; set; }
    public LoanApplication? LoanApplication { get; set; }

    public DocumentType Type { get; set; }
    public DocumentStatus Status { get; set; } = DocumentStatus.Uploaded;

    /// <summary>S3 bucket the object lives in — always "raw-documents" for applicant uploads.</summary>
    public string Bucket { get; set; } = default!;
    public string ObjectKey { get; set; } = default!;
    public string FileName { get; set; } = default!;
    public string ContentType { get; set; } = default!;

    public string? ValidationNotes { get; set; }

    public DateTimeOffset UploadedAt { get; set; }
    public DateTimeOffset? ValidatedAt { get; set; }
}
