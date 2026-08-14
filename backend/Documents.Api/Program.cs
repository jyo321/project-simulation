using Amazon.S3;
using Amazon.SimpleNotificationService;
using Amazon.SQS;
using Microsoft.EntityFrameworkCore;
using Northbridge.Shared.Aws;
using Northbridge.Shared.Data;
using Northbridge.Shared.Messaging;
using Northbridge.Shared.Storage;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddDbContext<NorthbridgeDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Northbridge")));

builder.Services.Configure<MessagingOptions>(builder.Configuration.GetSection("Messaging"));
builder.Services.Configure<BucketOptions>(builder.Configuration.GetSection("Buckets"));

builder.Services.AddDefaultAWSOptions(NorthbridgeAwsOptions.Build(builder.Configuration));
builder.Services.AddSingleton<IAmazonS3>(_ => new AmazonS3Client(NorthbridgeAwsOptions.BuildS3Config(builder.Configuration)));
builder.Services.AddAWSService<IAmazonSimpleNotificationService>();
builder.Services.AddAWSService<IAmazonSQS>();

builder.Services.AddScoped<IObjectStorageService, S3ObjectStorageService>();
builder.Services.AddScoped<IEventPublisher, SnsEventPublisher>();
builder.Services.AddScoped<IQueueSender, SqsQueueSender>();

builder.Services.AddAuthentication().AddJwtBearer(options =>
{
    options.Authority = builder.Configuration["Cognito:Authority"];
    options.Audience = builder.Configuration["Cognito:AppClientId"];
});
builder.Services.AddAuthorization();

// Allows any origin rather than a fixed AllowedOrigins list: this reference/demo build
// gets run from wherever (localhost, a VM's public IP, ...) and re-editing config per
// host defeats the point of a quick deploy. A real production deployment (behind
// CloudFront, per infra/terraform) should tighten this back to an explicit origin list.
builder.Services.AddCors(options =>
{
    options.AddPolicy("SpaOrigins", policy =>
        policy.SetIsOriginAllowed(_ => true)
            .AllowAnyHeader()
            .AllowAnyMethod());
});

builder.Services.AddHealthChecks();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("SpaOrigins");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

app.Run();

public class BucketOptions
{
    public string RawDocuments { get; set; } = default!;
    public string GeneratedDocuments { get; set; } = default!;
    public string Reports { get; set; } = default!;
}
