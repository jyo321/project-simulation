using System.Text.Json;
using Amazon.SQS;
using Amazon.SQS.Model;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Northbridge.Shared.Data;
using Northbridge.Shared.Entities;
using Northbridge.Shared.Events;

namespace StatusProjectorWorker;

/// <summary>
/// Service-triggered background service (brief §2.3.1): subscribed via SQS to the SNS
/// "application-events" topic (raw message delivery enabled — see infra/terraform/messaging.tf)
/// so it reacts to every ApplicationStatusChangedEvent published by any API, keeping the
/// denormalized ApplicationStatusProjection read model current for the Reviewer Console.
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
                QueueUrl = _options.StatusProjectorQueueUrl,
                MaxNumberOfMessages = 10,
                WaitTimeSeconds = 20,
                VisibilityTimeout = 30,
                MessageAttributeNames = new List<string> { "EventType" },
            }, stoppingToken);

            foreach (var message in response.Messages)
            {
                try
                {
                    await ProcessMessageAsync(message, stoppingToken);
                    await _sqs.DeleteMessageAsync(_options.StatusProjectorQueueUrl, message.ReceiptHandle, stoppingToken);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to process status-projector message {MessageId}", message.MessageId);
                }
            }
        }
    }

    private async Task ProcessMessageAsync(Message message, CancellationToken ct)
    {
        var eventType = message.MessageAttributes.TryGetValue("EventType", out var attr) ? attr.StringValue : null;
        if (eventType != nameof(ApplicationStatusChangedEvent))
        {
            // This worker only projects status changes; other event types on the same topic
            // (e.g. DecisionMadeEvent) are handled by other subscribers such as the notification worker.
            return;
        }

        var evt = JsonSerializer.Deserialize<ApplicationStatusChangedEvent>(message.Body)
            ?? throw new InvalidOperationException("Empty ApplicationStatusChangedEvent payload");

        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<NorthbridgeDbContext>();

        var projection = await db.ApplicationStatusProjections.FindAsync([evt.LoanApplicationId], ct);
        if (projection is null)
        {
            projection = new ApplicationStatusProjection { LoanApplicationId = evt.LoanApplicationId };
            db.ApplicationStatusProjections.Add(projection);
        }

        projection.Status = evt.NewStatus;
        projection.UpdatedAt = evt.OccurredAt;

        await db.SaveChangesAsync(ct);
        _logger.LogInformation("Projected status {NewStatus} for application {LoanApplicationId}", evt.NewStatus, evt.LoanApplicationId);
    }
}
