using System.Text;
using System.Text.Json;
using Amazon.Lambda.Core;
using Amazon.Lambda.Serialization.SystemTextJson;
using Amazon.S3;
using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Northbridge.Shared.Aws;
using Northbridge.Shared.Data;
using Northbridge.Shared.Enums;
using Northbridge.Shared.Storage;
using Npgsql;

[assembly: LambdaSerializer(typeof(DefaultLambdaJsonSerializer))]

namespace DailyStaleReportJob;

// Time-based trigger (brief §2.3.2): EventBridge Scheduler invokes this function once
// daily. Previously an ECS RunTask; moved to Lambda since a short, low-resource,
// once-a-day job doesn't need a standing Fargate task definition — Lambda bills only
// for the seconds it actually runs and needs no cluster/service to manage.
public class Function
{
    private readonly IServiceProvider _services;
    private readonly string _connectionString;

    // Runs once per execution environment ("cold start") and is reused across every
    // warm invocation on that environment, so DI/config wiring happens here rather
    // than in FunctionHandler.
    public Function()
    {
        var configuration = new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("appsettings.json", optional: true)
            .AddEnvironmentVariables()
            .Build();

        _connectionString = ResolveConnectionString(configuration);

        var services = new ServiceCollection();
        services.AddDbContext<NorthbridgeDbContext>(options => options.UseNpgsql(_connectionString));
        services.AddDefaultAWSOptions(NorthbridgeAwsOptions.Build(configuration));
        services.AddSingleton<IAmazonS3>(_ => new AmazonS3Client(NorthbridgeAwsOptions.BuildS3Config(configuration)));
        services.AddScoped<IObjectStorageService, S3ObjectStorageService>();
        services.Configure<JobOptions>(configuration.GetSection("Job"));

        _services = services.BuildServiceProvider();
    }

    // ECS could inject the DB connection string via the task definition's `secrets` block
    // (the ECS agent resolves it at container start, using the execution role); Lambda has
    // no equivalent mechanism, so when DbSecretArn is set (real AWS deployments) this
    // fetches it directly instead. Local/docker-compose runs never set DbSecretArn, so they
    // keep using ConnectionStrings:Northbridge exactly as every other worker does.
    private static string ResolveConnectionString(IConfiguration configuration)
    {
        var secretArn = configuration["DbSecretArn"];
        if (string.IsNullOrEmpty(secretArn))
        {
            return configuration.GetConnectionString("Northbridge")
                ?? throw new InvalidOperationException("Neither DbSecretArn nor ConnectionStrings:Northbridge is configured.");
        }

        using var secretsClient = new AmazonSecretsManagerClient();
        var response = secretsClient.GetSecretValueAsync(new GetSecretValueRequest { SecretId = secretArn }).GetAwaiter().GetResult();
        using var secretJson = JsonDocument.Parse(response.SecretString);
        return secretJson.RootElement.GetProperty("connectionString").GetString()!;
    }

    // EventBridge Scheduler invokes with whatever static JSON payload the schedule
    // target is configured with (none here) — the input is unused.
    public async Task FunctionHandler(JsonElement input, ILambdaContext context)
    {
        // Scheduler delivery is at-least-once, and a manual re-run is also possible, so
        // this job takes a Postgres advisory lock as its very first action to guarantee
        // it never double-fires concurrently — cheaper than a separate distributed-lock
        // service, and Postgres is already a hard dependency of the whole system.
        const long AdvisoryLockKey = 727100551;

        await using var lockConnection = new NpgsqlConnection(_connectionString);
        await lockConnection.OpenAsync();

        await using var lockCommand = new NpgsqlCommand("SELECT pg_try_advisory_lock(@key)", lockConnection);
        lockCommand.Parameters.AddWithValue("key", AdvisoryLockKey);
        var lockAcquired = (bool)(await lockCommand.ExecuteScalarAsync())!;

        if (!lockAcquired)
        {
            context.Logger.LogLine("Another DailyStaleReportJob invocation already holds the advisory lock. Exiting as a no-op.");
            return;
        }

        try
        {
            using var scope = _services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<NorthbridgeDbContext>();
            var storage = scope.ServiceProvider.GetRequiredService<IObjectStorageService>();
            var options = scope.ServiceProvider.GetRequiredService<IOptions<JobOptions>>().Value;

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

            context.Logger.LogLine($"Daily stale-application report written to s3://{options.ReportsBucket}/{reportKey} ({staleApplications.Count} applications)");
        }
        finally
        {
            await using var unlockCommand = new NpgsqlCommand("SELECT pg_advisory_unlock(@key)", lockConnection);
            unlockCommand.Parameters.AddWithValue("key", AdvisoryLockKey);
            await unlockCommand.ExecuteScalarAsync();
        }
    }
}

public class JobOptions
{
    public int StaleAfterDays { get; set; } = 5;
    public string ReportsBucket { get; set; } = default!;
}
