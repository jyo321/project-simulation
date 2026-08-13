using Amazon.S3;
using Amazon.SimpleNotificationService;
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
builder.Services.AddAWSService<IAmazonS3>();
builder.Services.AddAWSService<IAmazonSimpleNotificationService>();

builder.Services.AddScoped<IObjectStorageService, S3ObjectStorageService>();
builder.Services.AddScoped<IEventPublisher, SnsEventPublisher>();

builder.Services.AddAuthentication().AddJwtBearer(options =>
{
    options.Authority = builder.Configuration["Cognito:Authority"];
    options.Audience = builder.Configuration["Cognito:AppClientId"];
});
builder.Services.AddAuthorization();

builder.Services.AddCors(options =>
{
    options.AddPolicy("SpaOrigins", policy =>
        policy.WithOrigins(builder.Configuration.GetSection("AllowedOrigins").Get<string[]>() ?? Array.Empty<string>())
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
