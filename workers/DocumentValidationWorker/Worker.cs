using System.Text.Json;
using Amazon.SQS;
using Amazon.SQS.Model;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Northbridge.Shared.Data;
using Northbridge.Shared.Enums;

namespace DocumentValidationWorker;

/// <summary>
/// Service-triggered background service (brief §2.3.1): long-polls the "document-validation"
/// SQS queue that Documents.Api enqueues to on every confirmed upload. Runs as a standing
/// ECS Fargate service (not a one-shot RunTask) because it must always be ready to react to
/// the next upload event.
/// </summary>
public class Worker : BackgroundService
{
    private readonly IAmazonSQS _sqs;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly WorkerOptions _options;
    private readonly ILogger<Worker> _logger;

    public Worker(IAmazonSQS sqs, IServiceScopeFactory scopeFactory, IOptions<WorkerOptions> options, ILogger<Worker> logger)
    {
        _sqs = sqs;
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var response = await _sqs.ReceiveMessageAsync(new ReceiveMessageRequest
            {
                QueueUrl = _options.DocumentValidationQueueUrl,
                MaxNumberOfMessages = 10,
                WaitTimeSeconds = 20, // long-poll
                VisibilityTimeout = 60,
            }, stoppingToken);

            foreach (var message in response.Messages)
            {
                try
                {
                    await ProcessMessageAsync(message, stoppingToken);
                    await _sqs.DeleteMessageAsync(_options.DocumentValidationQueueUrl, message.ReceiptHandle, stoppingToken);
                }
                catch (Exception ex)
                {
                    // Do NOT delete on failure — the message becomes visible again after the
                    // visibility timeout and is retried, up to the queue's maxReceiveCount
                    // (see infra/terraform/messaging.tf), after which SQS moves it to the DLQ.
                    _logger.LogError(ex, "Failed to process document-validation message {MessageId}", message.MessageId);
                }
            }
        }
    }

    private async Task ProcessMessageAsync(Message message, CancellationToken ct)
    {
        var payload = JsonSerializer.Deserialize<DocumentValidationMessage>(message.Body)
            ?? throw new InvalidOperationException("Empty document-validation payload");

        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<NorthbridgeDbContext>();

        var document = await db.Documents.FindAsync([payload.DocumentId], ct);
        if (document is null)
        {
            _logger.LogWarning("Document {DocumentId} not found, skipping", payload.DocumentId);
            return;
        }

        // Stand-in for real OCR/completeness validation (e.g. Textract) — the point being
        // illustrated is the trigger/reliability pattern, not the analysis itself.
        document.Status = DocumentStatus.Validated;
        document.ValidationNotes = "Automated completeness check passed.";
        document.ValidatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync(ct);
        _logger.LogInformation("Validated document {DocumentId} for application {LoanApplicationId}", document.Id, payload.LoanApplicationId);
    }

    private record DocumentValidationMessage(Guid DocumentId, Guid LoanApplicationId, string Bucket, string ObjectKey);
}
