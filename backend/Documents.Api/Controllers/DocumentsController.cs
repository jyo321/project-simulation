using Documents.Api.Dtos;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Northbridge.Shared.Data;
using Northbridge.Shared.Entities;
using Northbridge.Shared.Enums;
using Northbridge.Shared.Messaging;
using Northbridge.Shared.Storage;

namespace Documents.Api.Controllers;

[ApiController]
[Route("api/documents")]
public class DocumentsController : ControllerBase
{
    private static readonly DocumentType[] RequiredDocumentTypes =
    {
        DocumentType.IdentityProof, DocumentType.IncomeProof, DocumentType.BankStatement,
    };

    private readonly NorthbridgeDbContext _db;
    private readonly IObjectStorageService _storage;
    private readonly IQueueSender _queueSender;
    private readonly MessagingOptions _messaging;
    private readonly BucketOptions _buckets;

    public DocumentsController(
        NorthbridgeDbContext db,
        IObjectStorageService storage,
        IQueueSender queueSender,
        IOptions<MessagingOptions> messaging,
        IOptions<BucketOptions> buckets)
    {
        _db = db;
        _storage = storage;
        _queueSender = queueSender;
        _messaging = messaging.Value;
        _buckets = buckets.Value;
    }

    /// <summary>
    /// Step 1 of the upload flow: create the Document row and hand back a pre-signed PUT URL.
    /// The applicant's browser uploads directly to S3 — this API never proxies file bytes.
    /// </summary>
    [HttpPost("upload-url")]
    public async Task<ActionResult<CreateUploadUrlResponse>> CreateUploadUrl(CreateUploadUrlRequest request, CancellationToken ct)
    {
        if (!Enum.TryParse<DocumentType>(request.Type, ignoreCase: true, out var docType))
        {
            return BadRequest($"Unknown document type '{request.Type}'.");
        }

        var objectKey = $"{request.LoanApplicationId}/{Guid.NewGuid()}-{request.FileName}";

        var document = new Document
        {
            LoanApplicationId = request.LoanApplicationId,
            Type = docType,
            Status = DocumentStatus.Uploaded,
            Bucket = _buckets.RawDocuments,
            ObjectKey = objectKey,
            FileName = request.FileName,
            ContentType = request.ContentType,
            UploadedAt = DateTimeOffset.UtcNow,
        };

        _db.Documents.Add(document);
        await _db.SaveChangesAsync(ct);

        var uploadUrl = _storage.GetPresignedUploadUrl(_buckets.RawDocuments, objectKey, request.ContentType, TimeSpan.FromMinutes(15));

        return Ok(new CreateUploadUrlResponse(document.Id, uploadUrl, _buckets.RawDocuments, objectKey));
    }

    /// <summary>
    /// Step 2: the browser calls this once the S3 PUT succeeds. This is the service-triggered
    /// path from the brief — it enqueues the Document Validation Worker via SQS, and if every
    /// required document type is now present, also kicks off the fire-and-forget Fraud/Forensics
    /// job (&gt;20 min) without blocking this request.
    /// </summary>
    [HttpPost("{id:guid}/confirm-upload")]
    public async Task<IActionResult> ConfirmUpload(Guid id, CancellationToken ct)
    {
        var document = await _db.Documents.FindAsync([id], ct);
        if (document is null) return NotFound();

        await _queueSender.SendAsync(_messaging.DocumentValidationQueueUrl, new
        {
            documentId = document.Id,
            loanApplicationId = document.LoanApplicationId,
            bucket = document.Bucket,
            objectKey = document.ObjectKey,
        }, ct);

        var uploadedTypes = await _db.Documents
            .Where(d => d.LoanApplicationId == document.LoanApplicationId && d.Status != DocumentStatus.Rejected)
            .Select(d => d.Type)
            .Distinct()
            .ToListAsync(ct);

        if (RequiredDocumentTypes.All(uploadedTypes.Contains))
        {
            var jobItem = new JobQueueItem
            {
                JobType = JobType.FraudForensics,
                LoanApplicationId = document.LoanApplicationId,
                Status = JobStatus.Queued,
                CreatedAt = DateTimeOffset.UtcNow,
            };
            _db.JobQueueItems.Add(jobItem);
            await _db.SaveChangesAsync(ct);

            await _queueSender.SendAsync(_messaging.FraudAnalysisQueueUrl, new
            {
                jobId = jobItem.Id,
                loanApplicationId = document.LoanApplicationId,
            }, ct);
        }

        return Accepted();
    }

    [HttpGet("{id:guid}/download-url")]
    public async Task<ActionResult<DownloadUrlResponse>> GetDownloadUrl(Guid id, CancellationToken ct)
    {
        var document = await _db.Documents.FindAsync([id], ct);
        if (document is null) return NotFound();

        var url = _storage.GetPresignedDownloadUrl(document.Bucket, document.ObjectKey, TimeSpan.FromMinutes(10));
        return Ok(new DownloadUrlResponse(url));
    }

    [HttpGet("by-application/{loanApplicationId:guid}")]
    public async Task<ActionResult<List<DocumentResponse>>> GetByApplication(Guid loanApplicationId, CancellationToken ct)
    {
        var documents = await _db.Documents
            .Where(d => d.LoanApplicationId == loanApplicationId)
            .Select(d => new DocumentResponse(d.Id, d.LoanApplicationId, d.Type.ToString(), d.Status.ToString(), d.FileName, d.UploadedAt, d.ValidatedAt))
            .ToListAsync(ct);

        return Ok(documents);
    }
}
