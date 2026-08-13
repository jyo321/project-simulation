using Applications.Api.Dtos;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Northbridge.Shared.Data;
using Northbridge.Shared.Entities;

namespace Applications.Api.Controllers;

[ApiController]
[Route("api/applicants")]
public class ApplicantsController : ControllerBase
{
    private readonly NorthbridgeDbContext _db;

    public ApplicantsController(NorthbridgeDbContext db)
    {
        _db = db;
    }

    [HttpPost]
    public async Task<ActionResult<ApplicantResponse>> Create(CreateApplicantRequest request, CancellationToken ct)
    {
        var applicant = new Applicant
        {
            FirstName = request.FirstName,
            LastName = request.LastName,
            Email = request.Email,
            Phone = request.Phone,
            CreatedAt = DateTimeOffset.UtcNow,
        };

        _db.Applicants.Add(applicant);
        await _db.SaveChangesAsync(ct);

        var response = new ApplicantResponse(applicant.Id, applicant.FirstName, applicant.LastName, applicant.Email, applicant.Phone);
        return CreatedAtAction(nameof(GetById), new { id = applicant.Id }, response);
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<ApplicantResponse>> GetById(Guid id, CancellationToken ct)
    {
        var applicant = await _db.Applicants.FindAsync([id], ct);
        if (applicant is null) return NotFound();

        return new ApplicantResponse(applicant.Id, applicant.FirstName, applicant.LastName, applicant.Email, applicant.Phone);
    }
}
