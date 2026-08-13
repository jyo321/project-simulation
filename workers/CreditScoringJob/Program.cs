using Amazon.Extensions.NETCore.Setup;
using Amazon.S3;
using Amazon.SimpleNotificationService;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Northbridge.Shared.Aws;
using Northbridge.Shared.Data;
using Northbridge.Shared.Entities;
using Northbridge.Shared.Enums;
using Northbridge.Shared.Events;
using Northbridge.Shared.Messaging;
using Northbridge.Shared.Storage;

// Fire-and-forget job (brief §2.3.3, >20 min, high CPU/mem): started by an EventBridge Pipe
// reading the "credit-scoring-jobs" SQS queue and invoking ecs:RunTask with the message body
// passed through as container environment overrides (JOB_ID / LOAN_APPLICATION_ID) — see
// infra/terraform/messaging.tf. This process is a one-shot task, not a standing service: it
// runs to completion and exits, with no ALB/API request lifetime to worry about.

var jobIdRaw = Environment.GetEnvironmentVariable("JOB_ID");
var loanApplicationIdRaw = Environment.GetEnvironmentVariable("LOAN_APPLICATION_ID");

if (!Guid.TryParse(jobIdRaw, out var jobId) || !Guid.TryParse(loanApplicationIdRaw, out var loanApplicationId))
{
    Console.Error.WriteLine("JOB_ID and LOAN_APPLICATION_ID environment variables are required.");
    Environment.Exit(1);
    return;
}

var builder = Host.CreateApplicationBuilder(Array.Empty<string>());

builder.Services.AddDbContext<NorthbridgeDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Northbridge")));

builder.Services.AddDefaultAWSOptions(NorthbridgeAwsOptions.Build(builder.Configuration));
builder.Services.AddAWSService<IAmazonS3>();
builder.Services.AddAWSService<IAmazonSimpleNotificationService>();
builder.Services.AddScoped<IObjectStorageService, S3ObjectStorageService>();
builder.Services.AddScoped<IEventPublisher, SnsEventPublisher>();
builder.Services.Configure<MessagingOptions>(builder.Configuration.GetSection("Messaging"));
builder.Services.Configure<JobOptions>(builder.Configuration.GetSection("Job"));

using var host = builder.Build();
var logger = host.Services.GetRequiredService<ILogger<Program>>();

using var scope = host.Services.CreateScope();
var db = scope.ServiceProvider.GetRequiredService<NorthbridgeDbContext>();
var storage = scope.ServiceProvider.GetRequiredService<IObjectStorageService>();
var eventPublisher = scope.ServiceProvider.GetRequiredService<IEventPublisher>();
var jobOptions = scope.ServiceProvider.GetRequiredService<Microsoft.Extensions.Options.IOptions<JobOptions>>().Value;

var jobItem = await db.JobQueueItems.FindAsync(jobId);
if (jobItem is null)
{
    logger.LogError("JobQueueItem {JobId} not found. Exiting.", jobId);
    Environment.Exit(1);
    return;
}

jobItem.Status = JobStatus.Running;
jobItem.StartedAt = DateTimeOffset.UtcNow;
await db.SaveChangesAsync();

try
{
    // Stand-in for a real credit-bureau integration (Experian/Equifax/TransUnion-style API),
    // which in production can legitimately take well over 20 minutes end-to-end (async
    // submission + polling/webhook callback). The ECS task has no application-imposed
    // timeout, so this is safe to let run long.
    var random = new Random();
    await Task.Delay(TimeSpan.FromSeconds(5));
    var riskScore = random.Next(300, 851);
    var bureauReference = $"BUREAU-{Guid.NewGuid():N}"[..20];

    var rawResponseKey = $"{loanApplicationId}/credit-report-{jobId}.json";
    var rawResponseBody = $"{{\"bureauReference\":\"{bureauReference}\",\"score\":{riskScore}}}";
    await storage.PutObjectAsync(jobOptions.GeneratedDocumentsBucket, rawResponseKey,
        new MemoryStream(System.Text.Encoding.UTF8.GetBytes(rawResponseBody)), "application/json");

    var creditReport = new CreditReport
    {
        LoanApplicationId = loanApplicationId,
        Score = riskScore,
        BureauReference = bureauReference,
        RawResponseBucket = jobOptions.GeneratedDocumentsBucket,
        RawResponseObjectKey = rawResponseKey,
        PulledAt = DateTimeOffset.UtcNow,
    };
    db.CreditReports.Add(creditReport);

    var application = await db.LoanApplications.FindAsync(loanApplicationId);
    if (application is not null)
    {
        var previousStatus = application.Status;
        application.RiskScore = riskScore;
        application.Status = LoanApplicationStatus.UnderReview;

        jobItem.Status = JobStatus.Succeeded;
        jobItem.CompletedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync();

        await eventPublisher.PublishAsync(new CreditScoringCompletedEvent
        {
            LoanApplicationId = loanApplicationId,
            OccurredAt = DateTimeOffset.UtcNow,
            RiskScore = riskScore,
        });

        await eventPublisher.PublishAsync(new ApplicationStatusChangedEvent
        {
            LoanApplicationId = loanApplicationId,
            OccurredAt = DateTimeOffset.UtcNow,
            PreviousStatus = previousStatus.ToString(),
            NewStatus = application.Status.ToString(),
        });
    }

    logger.LogInformation("Credit scoring job {JobId} completed with risk score {RiskScore} for application {LoanApplicationId}",
        jobId, riskScore, loanApplicationId);
}
catch (Exception ex)
{
    jobItem.Status = JobStatus.Failed;
    jobItem.ErrorMessage = ex.Message;
    jobItem.CompletedAt = DateTimeOffset.UtcNow;
    await db.SaveChangesAsync();

    logger.LogError(ex, "Credit scoring job {JobId} failed", jobId);
    Environment.Exit(1);
}

public class JobOptions
{
    public string GeneratedDocumentsBucket { get; set; } = default!;
}
