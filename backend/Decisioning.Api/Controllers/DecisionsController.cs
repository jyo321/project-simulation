using System.Text;
using Decisioning.Api.Dtos;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Northbridge.Shared.Data;
using Northbridge.Shared.Entities;
using Northbridge.Shared.Enums;
using Northbridge.Shared.Events;
using Northbridge.Shared.Messaging;
using Northbridge.Shared.Storage;

namespace Decisioning.Api.Controllers;

[ApiController]
[Route("api")]
public class DecisionsController : ControllerBase
{
    private readonly NorthbridgeDbContext _db;
    private readonly IEventPublisher _eventPublisher;
    private readonly IObjectStorageService _storage;
    private readonly BucketOptions _buckets;

    public DecisionsController(
        NorthbridgeDbContext db,
        IEventPublisher eventPublisher,
        IObjectStorageService storage,
        IOptions<BucketOptions> buckets)
    {
        _db = db;
        _eventPublisher = eventPublisher;
        _storage = storage;
        _buckets = buckets.Value;
    }

    /// <summary>
    /// The queue reviewers work from. Backed directly by the transactional tables here for
    /// simplicity; in a higher-traffic deployment this would instead read the denormalized
    /// projection the Application Status Projector worker maintains.
    /// </summary>
    [HttpGet("reviewer-queue")]
    public async Task<ActionResult<List<ReviewerQueueItem>>> GetQueue(CancellationToken ct)
    {
        var items = await _db.LoanApplications
            .Include(a => a.Applicant)
            .Where(a => a.Status == LoanApplicationStatus.UnderReview || a.Status == LoanApplicationStatus.Submitted)
            .OrderBy(a => a.SubmittedAt)
            .Select(a => new ReviewerQueueItem(
                a.Id,
                a.ApplicantId,
                a.Applicant!.FirstName + " " + a.Applicant!.LastName,
                a.RequestedAmount,
                a.Purpose,
                a.Status.ToString(),
                a.RiskScore,
                a.FraudFlagged,
                a.SubmittedAt))
            .ToListAsync(ct);

        return Ok(items);
    }

    /// <summary>
    /// Reviewer approves/rejects. Writes the Decision, generates the approval letter into the
    /// generated-documents bucket on approval, and publishes DecisionMadeEvent — the event the
    /// Notification Worker consumes to email/SMS the applicant with retry + DLQ semantics.
    /// </summary>
    [HttpPost("applications/{id:guid}/decision")]
    public async Task<ActionResult<DecisionResponse>> Decide(Guid id, MakeDecisionRequest request, CancellationToken ct)
    {
        var application = await _db.LoanApplications.Include(a => a.Applicant).FirstOrDefaultAsync(a => a.Id == id, ct);
        if (application is null) return NotFound();

        if (!Enum.TryParse<DecisionOutcome>(request.Outcome, ignoreCase: true, out var outcome))
        {
            return BadRequest($"Unknown outcome '{request.Outcome}'.");
        }

        var decision = new Decision
        {
            LoanApplicationId = application.Id,
            ReviewerId = request.ReviewerId,
            Outcome = outcome,
            Reason = request.Reason,
            DecidedAt = DateTimeOffset.UtcNow,
        };

        if (outcome == DecisionOutcome.Approved)
        {
            var letterKey = $"{application.Id}/approval-letter.txt";
            var letterBody = $"Dear {application.Applicant!.FirstName},\n\n" +
                              $"Your loan application for {application.RequestedAmount:C} has been approved.\n\n" +
                              "Regards,\nNorthbridge Lending";
            await _storage.PutObjectAsync(_buckets.GeneratedDocuments, letterKey,
                new MemoryStream(Encoding.UTF8.GetBytes(letterBody)), "text/plain", ct);
            decision.ApprovalLetterObjectKey = letterKey;
        }

        application.Status = outcome == DecisionOutcome.Approved ? LoanApplicationStatus.Approved : LoanApplicationStatus.Rejected;
        application.DecidedAt = decision.DecidedAt;

        _db.Decisions.Add(decision);
        await _db.SaveChangesAsync(ct);

        await _eventPublisher.PublishAsync(new DecisionMadeEvent
        {
            LoanApplicationId = application.Id,
            ApplicantId = application.ApplicantId,
            OccurredAt = decision.DecidedAt,
            Outcome = outcome.ToString(),
            Reason = request.Reason,
        }, ct);

        return Ok(new DecisionResponse(application.Id, outcome.ToString(), request.Reason, decision.DecidedAt));
    }
}
