using Applications.Api.Dtos;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Northbridge.Shared.Data;
using Northbridge.Shared.Entities;
using Northbridge.Shared.Enums;
using Northbridge.Shared.Events;
using Northbridge.Shared.Messaging;

namespace Applications.Api.Controllers;

[ApiController]
[Route("api/applications")]
public class LoanApplicationsController : ControllerBase
{
    private readonly NorthbridgeDbContext _db;
    private readonly IEventPublisher _eventPublisher;
    private readonly IQueueSender _queueSender;
    private readonly MessagingOptions _messaging;

    public LoanApplicationsController(
        NorthbridgeDbContext db,
        IEventPublisher eventPublisher,
        IQueueSender queueSender,
        IOptions<MessagingOptions> messaging)
    {
        _db = db;
        _eventPublisher = eventPublisher;
        _queueSender = queueSender;
        _messaging = messaging.Value;
    }

    [HttpPost]
    public async Task<ActionResult<LoanApplicationResponse>> Create(CreateLoanApplicationRequest request, CancellationToken ct)
    {
        var application = new LoanApplication
        {
            ApplicantId = request.ApplicantId,
            RequestedAmount = request.RequestedAmount,
            Purpose = request.Purpose,
            Status = LoanApplicationStatus.Draft,
            CreatedAt = DateTimeOffset.UtcNow,
        };

        _db.LoanApplications.Add(application);
        await _db.SaveChangesAsync(ct);

        return CreatedAtAction(nameof(GetById), new { id = application.Id }, ToResponse(application));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<LoanApplicationResponse>> GetById(Guid id, CancellationToken ct)
    {
        var application = await _db.LoanApplications.FindAsync([id], ct);
        if (application is null) return NotFound();

        return ToResponse(application);
    }

    /// <summary>
    /// Submits the application and enqueues the Credit Scoring & Risk Job. This is the
    /// fire-and-forget entry point described in the architecture brief: the API writes a
    /// JobQueueItem row and sends an SQS message inside the request, then returns 202
    /// immediately — it never waits on the >20 minute job itself.
    /// </summary>
    [HttpPost("{id:guid}/submit")]
    public async Task<IActionResult> Submit(Guid id, CancellationToken ct)
    {
        var application = await _db.LoanApplications.FindAsync([id], ct);
        if (application is null) return NotFound();

        if (application.Status != LoanApplicationStatus.Draft)
        {
            return Conflict($"Application {id} is not in Draft status.");
        }

        var previousStatus = application.Status;
        application.Status = LoanApplicationStatus.Submitted;
        application.SubmittedAt = DateTimeOffset.UtcNow;

        var jobItem = new JobQueueItem
        {
            JobType = JobType.CreditScoring,
            LoanApplicationId = application.Id,
            Status = JobStatus.Queued,
            CreatedAt = DateTimeOffset.UtcNow,
        };
        _db.JobQueueItems.Add(jobItem);

        // Business write + job-queue row commit together; the SQS send happens after commit
        // so we never record a job as queued if the transaction itself rolled back.
        await _db.SaveChangesAsync(ct);

        await _queueSender.SendAsync(_messaging.CreditScoringQueueUrl, new
        {
            jobId = jobItem.Id,
            loanApplicationId = application.Id,
        }, ct);

        await _eventPublisher.PublishAsync(new ApplicationStatusChangedEvent
        {
            LoanApplicationId = application.Id,
            OccurredAt = DateTimeOffset.UtcNow,
            PreviousStatus = previousStatus.ToString(),
            NewStatus = application.Status.ToString(),
        }, ct);

        return Accepted(new { applicationId = application.Id, jobId = jobItem.Id, status = application.Status.ToString() });
    }

    private static LoanApplicationResponse ToResponse(LoanApplication a) => new(
        a.Id, a.ApplicantId, a.RequestedAmount, a.Purpose, a.Status.ToString(), a.RiskScore, a.CreatedAt, a.SubmittedAt, a.DecidedAt);
}
