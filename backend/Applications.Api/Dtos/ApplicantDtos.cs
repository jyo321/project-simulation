namespace Applications.Api.Dtos;

public record CreateApplicantRequest(string FirstName, string LastName, string Email, string Phone);

public record ApplicantResponse(Guid Id, string FirstName, string LastName, string Email, string Phone);
