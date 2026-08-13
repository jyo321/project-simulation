using Amazon.Extensions.NETCore.Setup;
using Amazon.SQS;
using DocumentValidationWorker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Northbridge.Shared.Aws;
using Northbridge.Shared.Data;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddDbContext<NorthbridgeDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Northbridge")));

builder.Services.AddDefaultAWSOptions(NorthbridgeAwsOptions.Build(builder.Configuration));
builder.Services.AddAWSService<IAmazonSQS>();

builder.Services.Configure<WorkerOptions>(builder.Configuration.GetSection("Worker"));
builder.Services.AddHostedService<Worker>();

var host = builder.Build();
host.Run();
