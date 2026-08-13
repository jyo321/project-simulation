using System.Text;
using Amazon.Extensions.NETCore.Setup;
using Amazon.S3;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Northbridge.Shared.Aws;
using Northbridge.Shared.Data;
using Northbridge.Shared.Enums;
using Northbridge.Shared.Storage;
using Npgsql;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddDbContext<NorthbridgeDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Northbridge")));

builder.Services.AddDefaultAWSOptions(NorthbridgeAwsOptions.Build(builder.Configuration));
builder.Services.AddAWSService<IAmazonS3>();
builder.Services.AddScoped<IObjectStorageService, S3ObjectStorageService>();
builder.Services.Configure<JobOptions>(builder.Configuration.GetSection("Job"));

using var host = builder.Build();

var logger = host.Services.GetRequiredService<ILogger<Program>>();
var options = host.Services.GetRequiredService<IOptions<JobOptions>>().Value;
var connectionString = builder.Configuration.GetConnectionString("Northbridge")!;

// Time-based trigger (brief §2.3.2): EventBridge Scheduler invokes ecs:RunTask once daily.
// Scheduler delivery is at-least-once, and a manual re-run is also possible, so this job
// takes a Postgres advisory lock as its very first action to guarantee it never double-fires
// concurrently — cheaper than standing up a separate distributed-lock service, and Postgres
// is already a hard dependency of the whole system.
const long AdvisoryLockKey = 727100551;

await using var lockConnection = new NpgsqlConnection(connectionString);
await lockConnection.OpenAsync();

await using var lockCommand = new NpgsqlCommand("SELECT pg_try_advisory_lock(@key)", lockConnection);
lockCommand.Parameters.AddWithValue("key", AdvisoryLockKey);
var lockAcquired = (bool)(await lockCommand.ExecuteScalarAsync())!;

if (!lockAcquired)
{
    logger.LogWarning("Another DailyStaleReportJob instance already holds the advisory lock. Exiting as a no-op.");
    return;
}

try
{
    using var scope = host.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<NorthbridgeDbContext>();
    var storage = scope.ServiceProvider.GetRequiredService<IObjectStorageService>();

    var staleThreshold = DateTimeOffset.UtcNow.AddDays(-options.StaleAfterDays);
    var staleStatuses = new[] { LoanApplicationStatus.Submitted, LoanApplicationStatus.DocumentsPending, LoanApplicationStatus.UnderReview };

    var staleApplications = await db.LoanApplications
        .Include(a => a.Applicant)
        .Where(a => staleStatuses.Contains(a.Status) && a.SubmittedAt != null && a.SubmittedAt < staleThreshold)
        .OrderBy(a => a.SubmittedAt)
        .ToListAsync();

    var csv = new StringBuilder();
    csv.AppendLine("LoanApplicationId,ApplicantEmail,Status,RequestedAmount,SubmittedAt,DaysStale");
    foreach (var app in staleApplications)
    {
        var daysStale = (DateTimeOffset.UtcNow - app.SubmittedAt!.Value).Days;
        csv.AppendLine($"{app.Id},{app.Applicant!.Email},{app.Status},{app.RequestedAmount},{app.SubmittedAt:O},{daysStale}");
    }

    var reportKey = $"stale-applications/{DateTimeOffset.UtcNow:yyyy-MM-dd}.csv";
    await storage.PutObjectAsync(options.ReportsBucket, reportKey, new MemoryStream(Encoding.UTF8.GetBytes(csv.ToString())), "text/csv");

    logger.LogInformation("Daily stale-application report written to s3://{Bucket}/{Key} ({Count} applications)",
        options.ReportsBucket, reportKey, staleApplications.Count);
}
finally
{
    await using var unlockCommand = new NpgsqlCommand("SELECT pg_advisory_unlock(@key)", lockConnection);
    unlockCommand.Parameters.AddWithValue("key", AdvisoryLockKey);
    await unlockCommand.ExecuteScalarAsync();
}

public class JobOptions
{
    public int StaleAfterDays { get; set; } = 5;
    public string ReportsBucket { get; set; } = default!;
}
