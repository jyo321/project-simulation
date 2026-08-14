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
using Northbridge.Shared.Events;
using Northbridge.Shared.Messaging;
using Northbridge.Shared.Storage;

// Fire-and-forget job (brief §2.3.3, >20 min, high CPU/mem): started by an EventBridge Pipe
// reading the "fraud-analysis-jobs" SQS queue and invoking ecs:RunTask, same pattern as
// CreditScoringJob. This one runs bulk analysis across every document on the application
// (OCR cross-checks, tamper detection, duplicate-submission checks against the whole corpus),
// which is exactly the kind of workload that needs more CPU/memory than the request-serving
// API containers and cannot be squeezed inside an HTTP request lifetime.

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
builder.Services.AddSingleton<IAmazonS3>(_ => new AmazonS3Client(NorthbridgeAwsOptions.BuildS3Config(builder.Configuration)));
builder.Services.AddAWSService<IAmazonSimpleNotificationService>();
builder.Services.AddScoped<IObjectStorageService, S3ObjectStorageService>();
builder.Services.AddScoped<IEventPublisher, SnsEventPublisher>();
builder.Services.Configure<MessagingOptions>(builder.Configuration.GetSection("Messaging"));

using var host = builder.Build();
var logger = host.Services.GetRequiredService<ILogger<Program>>();

using var scope = host.Services.CreateScope();
var db = scope.ServiceProvider.GetRequiredService<NorthbridgeDbContext>();
var eventPublisher = scope.ServiceProvider.GetRequiredService<IEventPublisher>();

var jobItem = await db.JobQueueItems.FindAsync(jobId);
if (jobItem is null)
{
    logger.LogError("JobQueueItem {JobId} not found. Exiting.", jobId);
    Environment.Exit(1);
    return;
}

jobItem.Status = Northbridge.Shared.Enums.JobStatus.Running;
jobItem.StartedAt = DateTimeOffset.UtcNow;
await db.SaveChangesAsync();

try
{
    var documents = await db.Documents
        .Where(d => d.LoanApplicationId == loanApplicationId)
        .ToListAsync();

    // Stand-in for real bulk forensics (cross-document OCR consistency checks, tamper
    // detection, duplicate-submission lookups against the full document corpus) — the
    // point being illustrated is the async decoupling pattern, not the analysis itself.
    await Task.Delay(TimeSpan.FromSeconds(5));
    var flaggedForFraud = new Random().Next(0, 100) < 5; // ~5% flag rate, illustrative only

    var application = await db.LoanApplications.FindAsync(loanApplicationId);
    if (application is not null)
    {
        application.FraudFlagged = flaggedForFraud;

        jobItem.Status = Northbridge.Shared.Enums.JobStatus.Succeeded;
        jobItem.CompletedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync();

        await eventPublisher.PublishAsync(new FraudForensicsCompletedEvent
        {
            LoanApplicationId = loanApplicationId,
            OccurredAt = DateTimeOffset.UtcNow,
            FlaggedForFraud = flaggedForFraud,
        });
    }

    logger.LogInformation("Fraud forensics job {JobId} completed for application {LoanApplicationId} across {DocumentCount} documents (flagged={Flagged})",
        jobId, loanApplicationId, documents.Count, flaggedForFraud);
}
catch (Exception ex)
{
    jobItem.Status = Northbridge.Shared.Enums.JobStatus.Failed;
    jobItem.ErrorMessage = ex.Message;
    jobItem.CompletedAt = DateTimeOffset.UtcNow;
    await db.SaveChangesAsync();

    logger.LogError(ex, "Fraud forensics job {JobId} failed", jobId);
    Environment.Exit(1);
}
